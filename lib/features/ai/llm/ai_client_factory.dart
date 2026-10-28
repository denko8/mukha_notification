import '../../../features/settings/models/app_settings.dart';
import 'ai_provider.dart';
import 'chat_completion_client.dart';
import 'gigachat_client.dart';
import 'openai_compatible_client.dart';
import 'yandex_gpt_client.dart';

/// Создаёт клиента под выбранного в настройках провайдера.
class AiClientFactory {
  AiClientFactory._();

  static ChatCompletionClient build(AppSettings settings) {
    switch (AiProvider.fromName(settings.aiProvider)) {
      case AiProvider.yandexGpt:
        return YandexGptClient(
          apiKey: settings.aiApiKey.trim(),
          folderId: settings.yandexFolderId.trim(),
          model: settings.aiModel.isEmpty ? 'yandexgpt-lite' : settings.aiModel,
        );
      case AiProvider.gigaChat:
        return GigaChatClient(
          authKey: settings.gigaChatAuthKey.trim(),
          scope: settings.gigaChatScope,
          model: settings.aiModel.isEmpty ? 'GigaChat' : settings.aiModel,
        );
      case AiProvider.openaiCompatible:
        return OpenAiCompatibleClient(
          baseUrl: settings.aiBaseUrl,
          apiKey: settings.aiApiKey.trim(),
          model: settings.aiModel,
        );
    }
  }

  /// Достаточно ли данных, чтобы реально обращаться к модели.
  static bool isConfigured(AppSettings settings) {
    if (!settings.aiEnabled) return false;
    switch (AiProvider.fromName(settings.aiProvider)) {
      case AiProvider.yandexGpt:
        return settings.aiApiKey.trim().isNotEmpty &&
            settings.yandexFolderId.trim().isNotEmpty;
      case AiProvider.gigaChat:
        return settings.gigaChatAuthKey.trim().isNotEmpty;
      case AiProvider.openaiCompatible:
        return settings.aiApiKey.trim().isNotEmpty &&
            settings.aiBaseUrl.trim().isNotEmpty &&
            settings.aiModel.trim().isNotEmpty;
    }
  }
}
