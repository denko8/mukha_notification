import 'package:speech_to_text/speech_to_text.dart';

/// Абстракция голосового ввода (P2 ТЗ).
abstract class VoiceInputService {
  Future<bool> ensureAvailable();
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

  @override
  Future<bool> ensureAvailable() async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize();
      return _initialized;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> startListening({
    required void Function(String text) onText,
    required void Function(bool listening) onStatus,
    String localeId = 'ru_RU',
  }) async {
    final ok = await ensureAvailable();
    if (!ok) {
      onStatus(false);
      return;
    }
    await _speech.listen(
      onResult: (result) => onText(result.recognizedWords),
      listenFor: const Duration(minutes: 1),
      pauseFor: const Duration(seconds: 5),
      localeId: localeId,
      onSoundLevelChange: null,
    );
    _speech.statusListener = (status) =>
        onStatus(status == SpeechToText.listeningStatus);
  }

  @override
  Future<void> stopListening() => _speech.stop();
}

class NoopVoiceService implements VoiceInputService {
  @override
  Future<bool> ensureAvailable() async => false;
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
