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
    String localeId,
  });
  Future<void> stopListening();
}

/// Реализация на speech_to_text. Работает на Android, iOS и web
/// (в браузере — через Web Speech API, поддержка зависит от браузера).
class SpeechToTextVoiceService implements VoiceInputService {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  String? _lastError;

  @override
  Future<VoiceCheckResult> ensureAvailable() async {
    if (_initialized) return VoiceCheckResult.okResult;
    try {
      // Заранее проверяем разрешение: на части прошивок initialize()
      // возвращает false без внятной ошибки, и так мы хотя бы отличим
      // отказ в доступе от отсутствия сервиса распознавания.
      try {
        final hasPermission = await _speech.hasPermission;
        if (hasPermission == false) {
          return const VoiceCheckResult(VoiceAvailability.permissionDenied);
        }
      } catch (_) {
        // hasPermission поддерживается не на всех платформах — не мешаем
        // инициализации, решение примет сам initialize().
      }

      _lastError = null;
      final ok = await _speech.initialize(
        onError: (error) =>
            _lastError = '${error.errorMsg} (permanent=${error.permanent})',
      );
      if (!ok) {
        if (_lastError != null &&
            _lastError!.toLowerCase().contains('permission')) {
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
      _initialized = true;
      return VoiceCheckResult.okResult;
    } catch (e) {
      return VoiceCheckResult(
        VoiceAvailability.unavailable,
        technicalDetails: '$e',
      );
    }
  }

  @override
  Future<void> startListening({
    required void Function(String text) onText,
    required void Function(bool listening) onStatus,
    String localeId = 'ru_RU',
  }) async {
    final check = await ensureAvailable();
    if (!check.ok) {
      onStatus(false);
      return;
    }
    await _speech.listen(
      onResult: (result) => onText(result.recognizedWords),
      // В speech_to_text 7.x listenFor/pauseFor/localeId переехали
      // из аргументов listen() в SpeechListenOptions.
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 5),
        localeId: localeId,
      ),
    );
    _speech.statusListener = (status) =>
        onStatus(status == SpeechToText.listeningStatus);
  }

  @override
  Future<void> stopListening() => _speech.stop();
}

class NoopVoiceService implements VoiceInputService {
  @override
  Future<VoiceCheckResult> ensureAvailable() async =>
      const VoiceCheckResult(VoiceAvailability.noRecognitionService);

  @override
  Future<void> startListening({
    required void Function(String text) onText,
    required void Function(bool listening) onStatus,
    String localeId = 'ru_RU',
  }) async {
    onStatus(false);
  }

  @override
  Future<void> stopListening() async {}
}
