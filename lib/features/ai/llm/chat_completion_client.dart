/// Минимальный контракт чат-клиента: один запрос — текст ответа.
/// Абстракция позволяет подменять провайдера (YandexGPT, GigaChat,
/// OpenAI, Ollama) и тестировать без сети.
abstract class ChatCompletionClient {
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
  });
}

/// Ответ провайдера в неожиданном формате.
class LlmResponseException implements Exception {
  final String message;
  LlmResponseException([this.message = 'Некорректный ответ LLM']);
  @override
  String toString() => 'LlmResponseException: $message';
}
