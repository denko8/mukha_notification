import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'chat_completion_client.dart';

/// Клиент GigaChat (Сбер).
///
/// Поток: обмен ключа авторизации на access_token через OAuth (токен живёт
/// ~30 минут, кэшируется и обновляется заранее), затем chat/completions
/// в формате, близком к OpenAI.
///
/// Важно: боевые хосты GigaChat используют сертификаты Минцифры, которые
/// не доверяются стандартными устройствами. Варианты решения — в
/// docs/AI_PROVIDERS_YANDEX_GIGACHAT.md (бандл russiantrustedca.pem или
/// корпоративный шлюз с обычным TLS).
class GigaChatClient implements ChatCompletionClient {
  /// Ключ авторизации из личного кабинета GigaChat (используется в Basic).
  final String authKey;
  final String scope;
  final String model;
  final String oauthUrl;
  final String chatUrl;
  final http.Client _http;
  final Uuid _uuid;
  final Duration timeout;

  String? _accessToken;
  DateTime? _expiresAt;

  GigaChatClient({
    required this.authKey,
    this.scope = 'GIGACHAT_API_PERS',
    this.model = 'GigaChat',
    this.oauthUrl = 'https://ngw.devices.sberbank.ru:9443/api/v2/oauth',
    this.chatUrl =
        'https://gigachat.devices.sberbank.ru/api/v1/chat/completions',
    http.Client? client,
    Uuid? uuid,
    this.timeout = const Duration(seconds: 25),
  })  : _http = client ?? http.Client(),
        _uuid = uuid ?? const Uuid();

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final token = await _ensureToken();
    final response = await _http
        .post(
          Uri.parse(chatUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode({
            'model': model,
            'temperature': 0.1,
            'max_tokens': 600,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userPrompt},
            ],
          }),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmResponseException(
        'GigaChat HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final body = json.decode(utf8.decode(response.bodyBytes))
        as Map<String, dynamic>;
    final choices = body['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw LlmResponseException('GigaChat: пустой choices');
    }
    final content =
        (choices.first as Map<String, dynamic>)['message']?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw LlmResponseException('GigaChat: пустой content');
    }
    return content;
  }

  Future<String> _ensureToken() async {
    final now = DateTime.now();
    if (_accessToken != null &&
        _expiresAt != null &&
        now.isBefore(_expiresAt!.subtract(const Duration(minutes: 1)))) {
      return _accessToken!;
    }

    final response = await _http
        .post(
          Uri.parse(oauthUrl),
          headers: {
            'Authorization': 'Basic $authKey',
            'RqUID': _uuid.v4(),
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: 'scope=${Uri.encodeQueryComponent(scope)}',
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LlmResponseException(
        'GigaChat OAuth HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final body = json.decode(utf8.decode(response.bodyBytes))
        as Map<String, dynamic>;
    final token = body['access_token'];
    if (token is! String || token.isEmpty) {
      throw LlmResponseException('GigaChat: access_token не получен');
    }
    _accessToken = token;
    _expiresAt = _parseExpiry(body['expires_at']) ??
        now.add(const Duration(minutes: 25));
    return token;
  }

  /// GigaChat присылает expires_at как Unix-время в миллисекундах,
  /// но защищаемся и от строкового ISO-формата.
  static DateTime? _parseExpiry(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// Только для тестов: сбросить кэш токена.
  void invalidateToken() {
    _accessToken = null;
    _expiresAt = null;
  }
}
