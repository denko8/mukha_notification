import 'dart:convert';

import 'package:http/http.dart' as http;

import 'chat_completion_client.dart';

/// Клиент для любого OpenAI-совместимого эндпоинта:
/// OpenAI, шлюзы YandexGPT/GigaChat в совместимом режиме, локальная Ollama
/// (`http://localhost:11434/v1`), self-hosted прокси.
///
/// Ключи хранятся только в настройках на устройстве и уходят лишь
/// на указанный пользователем [baseUrl].
class OpenAiCompatibleClient implements ChatCompletionClient {
  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _http;
  final Duration timeout;

  OpenAiCompatibleClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _http = client ?? http.Client();

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final uri = Uri.parse('${_trimSlash(baseUrl)}/chat/completions');
    final response = await _http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: json.encode({
            'model': model,
            'temperature': 0.1,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userPrompt},
            ],
          }),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmResponseException(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw LlmResponseException('В ответе нет choices');
    }
    final content =
        (choices.first as Map<String, dynamic>)['message']?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw LlmResponseException('Пустой content в ответе');
    }
    return content;
  }

  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
