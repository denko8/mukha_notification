import 'dart:isolate';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Фаза жизненного цикла офлайн-модели распознавания речи.
enum VoiceModelPhase {
  /// Проверка ещё не выполнялась / модели нет.
  absent,

  /// Идёт скачивание zip-архива модели.
  downloading,

  /// Архив скачан, идёт распаковка.
  extracting,

  /// Модель готова к работе.
  ready,

  /// Загрузка или распаковка завершились ошибкой.
  error,
}

/// Состояние офлайн-модели Vosk.
@immutable
class VoiceModelState {
  final VoiceModelPhase phase;
  final double progress; // 0..1 на этапе downloading
  final int receivedBytes;
  final int totalBytes;
  final String? error;
  final String? modelPath;

  const VoiceModelState({
    required this.phase,
    this.progress = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
    this.modelPath,
  });

  const VoiceModelState.initial()
      : this(phase: VoiceModelPhase.absent);

  bool get isReady => phase == VoiceModelPhase.ready;

  VoiceModelState copyWith({
    VoiceModelPhase? phase,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? error,
    String? modelPath,
  }) {
    return VoiceModelState(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: error ?? this.error,
      modelPath: modelPath ?? this.modelPath,
    );
  }
}

/// Управление единственной русской Vosk-моделью: проверка наличия,
/// одноразовая загрузка (~45 МБ) с прогрессом, распаковка, очистка
/// битых артефактов. Модель лежит в каталоге документов приложения и
/// переживает переустановки поверх, но не попадает в APK.
class VoiceModelService extends StateNotifier<VoiceModelState> {
  VoiceModelService() : super(const VoiceModelState.initial());

  /// Маленькая русская модель Vosk — компромисс точности и размера
  /// (~45 МБ zip, ~90 МБ после распаковки, работает на CPU телефона).
  static const String modelName = 'vosk-model-small-ru-0.22';
  static const String modelUrl =
      'https://alphacephei.com/vosk/models/$modelName.zip';

  /// Каталог распакованных моделей: <docs>/models.
  Future<Directory> _modelsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'models'));
  }

  Future<Directory> _modelDir() async =>
      Directory(p.join((await _modelsDir()).path, modelName));

  /// Синхронизирует состояние с файловой системой (вызывается на старте).
  Future<void> checkExisting() async {
    try {
      final dir = await _modelDir();
      if (dir.existsSync() && dir.listSync().isNotEmpty) {
        state = VoiceModelState(
          phase: VoiceModelPhase.ready,
          progress: 1,
          modelPath: dir.path,
        );
        debugPrint('[VOSK] модель уже на месте: ${dir.path}');
      }
    } catch (e) {
      debugPrint('[VOSK] проверка модели не удалась: $e');
    }
  }

  /// Скачивает и распаковывает модель. Идемпотентна: повторный вызов
  /// во время загрузки игнорируется, готовая модель не качается заново.
  Future<void> download() async {
    if (state.phase == VoiceModelPhase.downloading ||
        state.phase == VoiceModelPhase.extracting) {
      return;
    }
    if (state.phase == VoiceModelPhase.ready) return;

    http.Client? client;
    File? zipFile;
    try {
      final modelsDir = await _modelsDir();
      if (!modelsDir.existsSync()) {
        modelsDir.createSync(recursive: true);
      }
      zipFile = File(p.join(modelsDir.path, '$modelName.zip'));
      if (zipFile.existsSync()) zipFile.deleteSync();

      state = const VoiceModelState(phase: VoiceModelPhase.downloading);
      client = http.Client();
      final request = http.Request('GET', Uri.parse(modelUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException(
          'сервер вернул ${response.statusCode} при загрузке модели',
        );
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = zipFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          state = state.copyWith(
            phase: VoiceModelPhase.downloading,
            receivedBytes: received,
            totalBytes: total,
            progress: total > 0 ? received / total : 0,
          );
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      debugPrint('[VOSK] архив скачан: ${zipFile.path} ($received байт)');

      state = state.copyWith(phase: VoiceModelPhase.extracting);
      final zipPath = zipFile.path;
      final outPath = modelsDir.path;
      // Распаковка в отдельном изоляте: 45 МБ zip не должны морозить UI.
      await Isolate.run(() => _extractZip(zipPath, outPath));

      final modelDir = Directory(p.join(outPath, modelName));
      if (!modelDir.existsSync() || modelDir.listSync().isEmpty) {
        throw const FileSystemException(
          'после распаковки каталог модели пуст или отсутствует',
        );
      }

      zipFile.deleteSync();
      state = VoiceModelState(
        phase: VoiceModelPhase.ready,
        progress: 1,
        receivedBytes: received,
        totalBytes: total,
        modelPath: modelDir.path,
      );
      debugPrint('[VOSK] модель готова: ${modelDir.path}');
    } catch (e) {
      debugPrint('[VOSK] загрузка модели не удалась: $e');
      try {
        zipFile?.deleteSync();
      } catch (_) {/* zip мог не создаться */}
      state = VoiceModelState(
        phase: VoiceModelPhase.error,
        error: '$e',
      );
    } finally {
      client?.close();
    }
  }

  /// Точка входа для изолята: decode + extractArchiveToDisk.
  static void _extractZip(String zipPath, String outPath) {
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    extractArchiveToDisk(archive, outPath);
  }
}
