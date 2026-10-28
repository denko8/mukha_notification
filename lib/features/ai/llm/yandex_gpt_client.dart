import 'dart:convert';

import 'package:http/http.dart' as http;

import 'chat_completion_client.dart';

/// Нативный клиент YandexGPT (Yandex Cloud Foundation Models).
///
/// Документация: POST https://llm.api.cloud.yandex.net/foundationModels/v1/completion
/// Авторизация сервисного аккаунта: заголовок `Authorization: Api-Key <ключ>`.
/// modelUri: gpt://<folderId>/<model>/latest, например
/// gpt://b1g.../yandexgpt-lite/latest.
class YandexGptClient implements ChatCompletionClient {
  final String apiKey;
  final String folderId;

  /// Короткое имя модели без префиксов, например `yandexgpt-lite`.
  final String model;
  final String endpoint;
  final http.Client _http;
  final Duration timeout;

  YandexGptClient({
    required this.apiKey,
    required this.folderId,
    this.model = 'yandexgpt-lite',
    this.endpoint =
        'https://llm.api.cloud.yandex.net/foundationModels/v1/completion',
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : _http = client ?? http.Client();

  String get _modelUri {
    // Если пользователь вписал полный modelUri — используем как есть.
    if (model.startsWith('gpt://') || model.startsWith('ds://')) return model;
    final base = model.endsWith('/latest') ? model : '$model/latest';
    return 'gpt://$folderId/$base';
  }

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final response = await _http
        .post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Api-Key $apiKey',
          },
          body: json.encode({
            'modelUri': _modelUri,
            'completionOptions': {
              'stream': false,
              'temperature': 0.1,
              'maxTokens': 600,
            },
            'messages': [
              {'role': 'system', 'text': systemPrompt},
              {'role': 'user', 'text': userPrompt},
            ],
          }),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmResponseException(
        'YandexGPT HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final body = json.decode(utf8.decode(response.bodyBytes))
        as Map<String, dynamic>;
    final alternatives =
        body['result']?['alternatives'] as List<dynamic>?;
    if (alternatives == null || alternatives.isEmpty) {
      throw LlmResponseException('YandexGPT: пустой alternatives');
    }
    final text = (alternatives.first
        as Map<String, dynamic>)['message']?['text'];
    if (text is! String || text.trim().isEmpty) {
      throw LlmResponseException('YandexGPT: пустой текст ответа');
    }
    return text;
  }
}
