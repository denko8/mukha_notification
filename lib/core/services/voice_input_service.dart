import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Причина недоступности голосового ввода — чтобы UI показывал
/// конкретную подсказку, а не общее «проверьте разрешение».
enum VoiceAvailability {
  /// Всё готово, можно вызывать listen.
  available,

  /// Пользователь не выдал разрешение на запись аудио.
  permissionDenied,

  /// Разрешение есть, но в системе нет провайдера распознавания речи
  /// (на части китайских прошивок без Google-приложений и сервисов речи).
  noRecognitionService,

  /// Любая другая ошибка инициализации.
  unavailable,
}

/// Результат проверки готовности голосового ввода.
class VoiceCheckResult {
  final VoiceAvailability availability;

  /// Техническая детализация для диагностики (текст ошибки плагина).
  final String? technicalDetails;

  const VoiceCheckResult(this.availability, {this.technicalDetails});

  bool get ok => availability == VoiceAvailability.available;

  static const okResult = VoiceCheckResult(VoiceAvailability.available);
}

/// Абстракция голосового ввода (P2 ТЗ).
abstract class VoiceInputService {
  Future<VoiceCheckResult> ensureAvailable();
  Future<void> startListening({
    required void Function(String text) onText,
    required void Function(bool listening) onStatus,
    void Function(String message)? onError,
    String localeId,
  });
  Future<void> stopListening();
}

/// Реализация на speech_to_text 7.x. Работает на Android, iOS и web
/// (в браузере — через Web Speech API, поддержка зависит от браузера).
class SpeechToTextVoiceService implements VoiceInputService {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  String? _lastError;

  @override
  Future<VoiceCheckResult> ensureAvailable() async {
    if (_initialized) return VoiceCheckResult.okResult;
    try {
      // ВАЖНО: нельзя пре-чекать hasPermission и выходить до initialize() —
      // на первом запуске разрешение ещё не запрашивалось, hasPermission
      // вернёт false, а системный диалог показывает именно initialize().
      // Поэтому всегда даём инициализации отработать, причину сбоя
      // разбираем после.
      _lastError = null;
      final ok = await _speech.initialize(
        onError: (error) {
          _lastError = '${error.errorMsg} (permanent=${error.permanent})';
          debugPrint('[STT] initialize onError: $_lastError');
        },
        // В debug-режиме плагин пишет свой канал в логкат — видно,
        // доходит ли до него аудио и ответы системного движка.
        debugLogging: kDebugMode,
      );
      debugPrint('[STT] initialize -> $ok, lastError=$_lastError');
      if (ok) {
        _initialized = true;
        return VoiceCheckResult.okResult;
      }
      return _classifyFailure();
    } catch (e) {
      debugPrint('[STT] initialize threw: $e');
      return VoiceCheckResult(
        VoiceAvailability.unavailable,
        technicalDetails: '$e',
      );
    }
  }

  /// Различает отказ в разрешении и отсутствие сервиса распознавания
  /// после неуспешной инициализации.
  Future<VoiceCheckResult> _classifyFailure() async {
    final error = _lastError?.toLowerCase() ?? '';
    if (error.contains('permission') ||
        error.contains('audio') ||
        error.contains('recorder')) {
      return VoiceCheckResult(
        VoiceAvailability.permissionDenied,
        technicalDetails: _lastError,
      );
    }
    bool? granted;
    try {
      granted = await _speech.hasPermission;
    } catch (_) {
      granted = null;
    }
    if (granted == false) {
      return VoiceCheckResult(
        VoiceAvailability.permissionDenied,
        technicalDetails: _lastError,
      );
    }
    return VoiceCheckResult(
      VoiceAvailability.noRecognitionService,
      technicalDetails: _lastError,
    );
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
      onError?.call(check.technicalDetails ?? 'сервис распознавания недоступен');
      return;
    }

    // Подбираем локаль, которую движок реально умеет:
    // запрошенная ru_RU -> любой русский вариант -> null (язык системы).
    // null важен: если жёстко передать неподдерживаемую локаль, часть
    // движков молча не возвращает результаты — микрофон «горит», но
    // распознанного текста нет.
    String? effectiveLocale = localeId;
    try {
      final available = await _speech.locales();
      final ids = available.map((e) => e.localeId).toList();
      debugPrint('[STT] доступные локали (${ids.length}): $ids');
      if (!ids.contains(localeId)) {
        final ru = ids.firstWhere(
          (id) => id.toLowerCase().startsWith('ru'),
          orElse: () => '',
        );
        effectiveLocale = ru.isNotEmpty ? ru : null;
      }
    } catch (e) {
      // Список локалей недоступен — не навязываем ничего, берём систему.
      debugPrint('[STT] locales() threw: $e — использую системный язык');
      effectiveLocale = null;
    }
    debugPrint('[STT] выбрана локаль: $effectiveLocale');

    // В API speech_to_text 7.x у listen() нет параметра onError:
    // ошибки и статус приходят через публичные поля errorListener и
    // statusListener. Назначаем их ДО listen() — иначе первые события
    // (в т.ч. мгновенный отказ сервиса) теряются и кнопка «молчит».
    // Тип аргумента берём из публичного typedef SpeechErrorListener,
    // сам класс SpeechRecognitionError пакетом не экспортируется.
    final SpeechErrorListener errorHandler = (error) {
      debugPrint(
          '[STT] errorListener: ${error.errorMsg} permanent=${error.permanent}');
      onStatus(false);
      onError?.call(error.errorMsg);
    };
    _speech.errorListener = errorHandler;
    _speech.statusListener = (status) {
      debugPrint('[STT] status: $status');
      onStatus(status == SpeechToText.listeningStatus);
    };

    debugPrint('[STT] listen() старт, localeId=$effectiveLocale');
    await _speech.listen(
      onResult: (result) {
        debugPrint(
            '[STT] result: final=${result.finalResult} '
            'words="${result.recognizedWords}"');
        if (result.recognizedWords.isNotEmpty) onText(result.recognizedWords);
      },
      // listenFor/pauseFor/localeId в 7.x остаются именованными
      // параметрами listen() (в SpeechListenOptions их нет).
      listenFor: const Duration(minutes: 1),
      pauseFor: const Duration(seconds: 5),
      localeId: effectiveLocale,
    );
  }

  @override
  Future<void> stopListening() {
    debugPrint('[STT] stop()');
    return _speech.stop();
  }
}

class NoopVoiceService implements VoiceInputService {
  @override
  Future<VoiceCheckResult> ensureAvailable() async =>
      const VoiceCheckResult(VoiceAvailability.noRecognitionService);

  @override
  Future<void> startListening({
    required void Function(String text) onText,
    required void Function(bool listening) onStatus,
    void Function(String message)? onError,
    String localeId = 'ru_RU',
  }) async {
    onStatus(false);
  }

  @override
  Future<void> stopListening() async {}
}
