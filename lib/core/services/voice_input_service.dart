/// Причина недоступности голосового ввода — чтобы UI показывал
/// конкретную подсказку, а не общее «проверьте разрешение».
enum VoiceAvailability {
  /// Всё готово, можно начинать запись.
  available,

  /// Пользователь не выдал разрешение на запись аудио.
  permissionDenied,

  /// Офлайн-модель распознавания ещё не скачана на устройство.
  modelNotDownloaded,

  /// Любая другая ошибка инициализации движка.
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
/// Боевой реализация — [VoskVoiceService] (офлайн, своя модель).
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

/// Заглушка для платформ без Vosk (web/iOS) и тестов.
class NoopVoiceService implements VoiceInputService {
  @override
  Future<VoiceCheckResult> ensureAvailable() async =>
      const VoiceCheckResult(VoiceAvailability.modelNotDownloaded);

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
