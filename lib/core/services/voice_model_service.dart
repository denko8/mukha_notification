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

  /// Read-only snapshot for services outside the StateNotifier subclass.
  VoiceModelState get currentState => state;

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

  /// Синхронизирует состояние с файловой системой (вызывается на старте).
  Future<void> checkExisting() async {
    try {
      final modelsDir = await _modelsDir();
      // Только каталог с реальной структурой Vosk (am/conf/graph)
      // считается готовой моделью — пустой огрызок прошлой попытки нет.
      final dir = _findModelDir(modelsDir);
      if (dir != null) {
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
      client = http.Client();

      // Если zip уже полностью скачан (например, прошлая попытка упала
      // на этапе распаковки), не качаем 46 МБ повторно.
      final total = await _downloadIfNeeded(client, zipFile);
      final received = zipFile.lengthSync();
      debugPrint('[VOSK] архив готов: ${zipFile.path} ($received байт)');

      state = state.copyWith(phase: VoiceModelPhase.extracting);
      final zipPath = zipFile.path;
      final outPath = modelsDir.path;
      // Распаковка в отдельном изоляте: 45 МБ zip не должны морозить UI.
      final extracted = await Isolate.run(() => _extractZip(zipPath, outPath));
      debugPrint('[VOSK] распаковано записей: $extracted');
      debugPrint(
        '[VOSK] содержимое $outPath: '
        '${modelsDir.listSync().map((e) => p.basename(e.path)).toList()}',
      );

      final modelDir = _findModelDir(modelsDir);
      if (modelDir == null) {
        throw const FileSystemException(
          'после распаковки каталог модели не найден '
          '(ожидаются подкаталоги am/conf/graph)',
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
      // zip намеренно НЕ удаляем: если он скачан полностью, повторная
      // попытка переиспользует его и сразу перейдёт к распаковке.
      // Неполный/битый архив отбракует _downloadIfNeeded по размеру.
      state = VoiceModelState(
        phase: VoiceModelPhase.error,
        error: '$e',
      );
    } finally {
      client?.close();
    }
  }

  /// Качает архив с прогрессом, либо переиспользует уже скачанный
  /// полный zip. Возвращает ожидаемый общий размер в байтах.
  Future<int> _downloadIfNeeded(http.Client client, File zipFile) async {
    // HEAD: ожидаемый размер для проверки полноты локального архива.
    int? expectedSize;
    try {
      final head = await client.head(Uri.parse(modelUrl));
      expectedSize = int.tryParse(head.headers['content-length'] ?? '');
    } catch (e) {
      debugPrint('[VOSK] HEAD не удался: $e, проверю zip-сигнатурой');
    }

    if (zipFile.existsSync() && zipFile.lengthSync() > 0) {
      final size = zipFile.lengthSync();
      final sizeOk = expectedSize == null || size == expectedSize;
      var sigOk = expectedSize == null;
      if (!sigOk) {
        final raf = zipFile.openSync();
        try {
          final sig = raf.readSync(4);
          sigOk = sig.length == 4 &&
              sig[0] == 0x50 && // P
              sig[1] == 0x4B && // K
              sig[2] == 0x03 &&
              sig[3] == 0x04;
        } finally {
          raf.closeSync();
        }
      }
      if (sizeOk && sigOk) {
        debugPrint('[VOSK] zip уже скачан ($size байт), распаковываю');
        state = state.copyWith(
          phase: VoiceModelPhase.downloading,
          progress: 1,
          receivedBytes: size,
          totalBytes: expectedSize ?? size,
        );
        return expectedSize ?? size;
      }
      debugPrint('[VOSK] локальный zip неполный, удаляю и качаю заново');
      zipFile.deleteSync();
    }

    state = const VoiceModelState(phase: VoiceModelPhase.downloading);
    final request = http.Request('GET', Uri.parse(modelUrl));
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw HttpException(
        'сервер вернул ${response.statusCode} при загрузке модели',
      );
    }

    final total = response.contentLength ?? expectedSize ?? 0;
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
    return total;
  }

  /// Точка входа для изолята: decode + extractArchiveToDisk.
  ///
  /// ВАЖНО: функция асинхронная и возвращает Future — иначе
  /// [Isolate.run] завершает изолят сразу после синхронного старта
  /// extractArchiveToDisk, обрывая запись файлов (распаковка давала
  /// пустой каталог). Возвращаем число извлечённых файлов для лога.
  static Future<int> _extractZip(String zipPath, String outPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    debugPrint('[VOSK] файлов в архиве: ${archive.files.length}');
    await extractArchiveToDisk(archive, outPath);
    return archive.files.length;
  }

  /// Ищет распакованный каталог модели: сначала по ожидаемому имени,
  /// затем по характерным подкаталогам Vosk (am/conf/graph) — на случай
  /// иной структуры архива.
  static Directory? _findModelDir(Directory modelsDir) {
    final direct = Directory(p.join(modelsDir.path, modelName));
    if (_looksLikeModel(direct)) return direct;
    if (!modelsDir.existsSync()) return null;
    for (final entity in modelsDir.listSync()) {
      if (entity is Directory && _looksLikeModel(entity)) return entity;
    }
    return null;
  }

  static bool _looksLikeModel(Directory dir) {
    if (!dir.existsSync()) return false;
    bool has(String name) => Directory(p.join(dir.path, name)).existsSync();
    // У моделей Vosk обязательно есть conf и хотя бы один из am/graph.
    return has('conf') && (has('am') || has('graph'));
  }
}
