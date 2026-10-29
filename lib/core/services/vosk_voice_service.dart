import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

import 'voice_input_service.dart';
import 'voice_model_service.dart';

/// Офлайновый голосовой ввод на Vosk.
///
/// Модель скачивается один раз [VoiceModelService.download] и лежит в
/// каталоге документов; системный RecognitionService и Google-сервисы
/// не нужны — распознавание полностью локальное.
class VoskVoiceService implements VoiceInputService {
  VoskVoiceService(this._models);

  final VoiceModelService _models;
  final VoskFlutterPlugin _plugin = VoskFlutterPlugin.instance();

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speech;
  StreamSubscription<String>? _partialSub;
  StreamSubscription<String>? _resultSub;

  // Накопленный текст текущей сессии: финализированные фразы +
  // текущая «живая» partial-строка.
  String _committed = '';
  String _partial = '';

  @override
  Future<VoiceCheckResult> ensureAvailable() async {
    final st = _models.currentState;
    if (st.phase != VoiceModelPhase.ready || st.modelPath == null) {
      return const VoiceCheckResult(
        VoiceAvailability.modelNotDownloaded,
      );
    }
    final status = await Permission.microphone.status;
    if (status.isDenied ||
        status.isRestricted ||
        status.isPermanentlyDenied) {
      return VoiceCheckResult(
        VoiceAvailability.permissionDenied,
        technicalDetails: 'microphone status: $status',
      );
    }
    return VoiceCheckResult.okResult;
  }

  @override
  Future<void> startListening({
    required void Function(String text) onText,
    required void Function(bool listening) onStatus,
    void Function(String message)? onError,
    String localeId = 'ru_RU',
  }) async {
    final check = await ensureAvailable();
    if (!check.ok) {
      onStatus(false);
      onError?.call(check.technicalDetails ?? 'движок не готов');
      return;
    }

    try {
      // Модель и сервис создаём один раз: загрузка модели в память
      // занимает 1–3 секунды, повторно платить этой ценой нельзя.
      if (_model == null) {
        debugPrint('[VOSK] загрузка модели в память…');
        _model = await _plugin.createModel(_models.currentState.modelPath!);
      }
      _recognizer ??= await _plugin.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );
      await _recognizer!.reset();
      _speech ??= await _plugin.initSpeechService(_recognizer!);

      _committed = '';
      _partial = '';

      await _partialSub?.cancel();
      await _resultSub?.cancel();
      _partialSub = _speech!.onPartial().listen((json) {
        final text = _extract(json, 'partial');
        if (text == _partial) return;
        _partial = text;
        if (text.isNotEmpty) onText(_sessionText());
      });
      _resultSub = _speech!.onResult().listen((json) {
        final text = _extract(json, 'text');
        if (text.isEmpty) return;
        _committed =
            _committed.isEmpty ? text : '$_committed $text';
        _partial = '';
        onText(_sessionText());
      });

      await _speech!.start(
        onRecognitionError: (error) {
          debugPrint('[VOSK] ошибка записи: $error');
          onStatus(false);
          onError?.call('$error');
        },
      );
      debugPrint('[VOSK] запись начата');
      onStatus(true);
    } catch (e) {
      debugPrint('[VOSK] старт записи не удался: $e');
      onStatus(false);
      onError?.call('$e');
    }
  }

  @override
  Future<void> stopListening() async {
    debugPrint('[VOSK] стоп');
    try {
      await _speech?.stop();
    } catch (e) {
      debugPrint('[VOSK] stop() бросил: $e');
    }
    await _partialSub?.cancel();
    await _resultSub?.cancel();
    _partialSub = null;
    _resultSub = null;
    _partial = '';
  }

  String _sessionText() => [_committed, _partial]
      .where((s) => s.isNotEmpty)
      .join(' ')
      .trim();

  String _extract(String json, String key) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return (map[key] as String?)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }
}
