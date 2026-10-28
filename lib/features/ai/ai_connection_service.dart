import '../../features/settings/models/app_settings.dart';
import 'llm/ai_client_factory.dart';
import 'llm/chat_completion_client.dart';

/// Результат проверки настроек ИИ.
class AiConnectionResult {
  final bool ok;
  final String message;

  const AiConnectionResult(this.ok, this.message);
}

/// Делает минимальный запрос к выбранному провайдеру, чтобы пользователь
/// сразу понял, верны ли ключ/идентификаторы и доступна ли сеть.
class AiConnectionService {
  Future<AiConnectionResult> test(AppSettings settings) async {
    if (!AiClientFactory.isConfigured(settings)) {
      return const AiConnectionResult(
        false,
        'Заполните обязательные поля выбранного провайдера',
      );
    }
    final ChatCompletionClient client = AiClientFactory.build(settings);
    try {
      final reply = await client.complete(
        systemPrompt:
            'Ответь строго одним словом: ok. Никаких пояснений.',
        userPrompt: 'Проверка связи',
      );
      final trimmed = reply.trim().toLowerCase();
      // Не требуем точного "ok" — у моделей бывает пунктуация/регистр.
      final alive = trimmed.contains('ok') || trimmed.length < 40;
      return AiConnectionResult(
        alive,
        alive ? 'Подключение работает' : 'Неожиданный ответ: $trimmed',
      );
    } on LlmResponseException catch (e) {
      return AiConnectionResult(false, e.message);
    } catch (e) {
      return AiConnectionResult(false, 'Сбой соединения: $e');
    }
  }
}
