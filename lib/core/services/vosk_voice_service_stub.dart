import 'voice_input_service.dart';

/// Compile-time substitute: browser builds must never import native Vosk/FFI.
/// The provider selects NoopVoiceService on unsupported platforms.
class VoskVoiceService extends NoopVoiceService {
  VoskVoiceService(Object models);
}
