import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:smart_notes/features/ai/llm/ai_client_factory.dart';
import 'package:smart_notes/features/ai/llm/ai_provider.dart';
import 'package:smart_notes/features/ai/llm/chat_completion_client.dart';
import 'package:smart_notes/features/ai/llm/gigachat_client.dart';
import 'package:smart_notes/features/ai/llm/yandex_gpt_client.dart';
import 'package:smart_notes/features/settings/models/app_settings.dart';

/// Управляемый фейковый HTTP-клиент: пишет запросы и отдаёт заготовленные ответы.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  final Map<String, String> _bodies = {};
  final http.StreamedResponse Function(http.BaseRequest req) handler;

  _FakeHttp(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request is http.Request) {
      _bodies[request.url.path] = request.body;
    }
    return handler(request);
  }

  String bodyOf(String pathPart) => _bodies.entries
      .firstWhere((e) => e.key.contains(pathPart))
      .value;
}

http.StreamedResponse _json(String body, [int code = 200]) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      code,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('YandexGptClient', () {
    test('шлёт Api-Key, modelUri и парсит alternatives', () async {
      late http.BaseRequest captured;
      final httpClient = _FakeHttp((req) {
        captured = req;
        return _json(jsonEncode({
          'result': {
            'alternatives': [
              {
                'message': {'role': 'assistant', 'text': '{"reminderAt":null}'}
              }
            ]
          }
        }));
      });
      final client = YandexGptClient(
        apiKey: 'AQVN123',
        folderId: 'b1gfolder',
        model: 'yandexgpt-lite',
        client: httpClient,
      );

      final text = await client.complete(
        systemPrompt: 'sys',
        userPrompt: 'usr',
      );

      expect(text, contains('reminderAt'));
      expect(captured.headers['Authorization'], 'Api-Key AQVN123');
      expect(captured.url.path, contains('foundationModels/v1/completion'));
      final body = jsonDecode(httpClient.bodyOf('completion')) as Map<String, dynamic>;
      expect(body['modelUri'], 'gpt://b1gfolder/yandexgpt-lite/latest');
      expect(body['messages'].first['role'], 'system');
    });

    test('полный modelUri пользователя не перестраивается', () async {
      late http.BaseRequest captured;
      final client = YandexGptClient(
        apiKey: 'k',
        folderId: 'f',
        model: 'gpt://custom-folder/yandexgpt-pro/latest',
        client: _FakeHttp((req) {
          captured = req;
          return _json(
              '{"result":{"alternatives":[{"message":{"text":"ok"}}]}}');
        }),
      );
      await client.complete(systemPrompt: 's', userPrompt: 'u');
      final body = jsonDecode(captured is http.Request
          ? (captured as http.Request).body
          : '{}') as Map<String, dynamic>;
      expect(body['modelUri'], 'gpt://custom-folder/yandexgpt-pro/latest');
    });

    test('ошибка HTTP превращается в LlmResponseException', () async {
      final client = YandexGptClient(
        apiKey: 'k',
        folderId: 'f',
        client: _FakeHttp((_) => _json('denied', 401)),
      );
      expect(
        () => client.complete(systemPrompt: 's', userPrompt: 'u'),
        throwsA(isA<LlmResponseException>()),
      );
    });
  });

  group('GigaChatClient', () {
    test('OAuth один раз на серию запросов, токен кэшируется', () async {
      var oauthHits = 0;
      final httpClient = _FakeHttp((req) {
        if (req.url.path.contains('oauth')) {
          oauthHits++;
          return _json(jsonEncode({
            'access_token': 'tok-123',
            // далёкое будущее в миллисекундах
            'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
          }));
        }
        return _json(jsonEncode({
          'choices': [
            {
              'message': {'content': '{"category":"general"}'}
            }
          ]
        }));
      });
      final client = GigaChatClient(
        authKey: 'basic-key',
        client: httpClient,
      );

      await client.complete(systemPrompt: 's', userPrompt: 'u1');
      await client.complete(systemPrompt: 's', userPrompt: 'u2');

      expect(oauthHits, 1);
      final oauthReq = httpClient.requests.first;
      expect(oauthReq.headers['Authorization'], 'Basic basic-key');
      expect(oauthReq.headers['RqUID'], isNotEmpty);
      final chatReq = httpClient.requests.firstWhere(
          (r) => r.url.path.contains('chat/completions'));
      expect(chatReq.headers['Authorization'], 'Bearer tok-123');
    });

    test('истёкший токен обновляется повторным OAuth', () async {
      var oauthHits = 0;
      final httpClient = _FakeHttp((req) {
        if (req.url.path.contains('oauth')) {
          oauthHits++;
          return _json(jsonEncode({
            'access_token': 'tok-new',
            'expires_at': DateTime.now()
                .subtract(const Duration(minutes: 10))
                .millisecondsSinceEpoch,
          }));
        }
        return _json(jsonEncode({
          'choices': [
            {
              'message': {'content': 'ok'}
            }
          ]
        }));
      });
      final client = GigaChatClient(authKey: 'k', client: httpClient);

      await client.complete(systemPrompt: 's', userPrompt: 'u1');
      await client.complete(systemPrompt: 's', userPrompt: 'u2');
      expect(oauthHits, 2);
    });

    test('ошибка OAuth пробрасывается как LlmResponseException', () async {
      final client = GigaChatClient(
        authKey: 'k',
        client: _FakeHttp((_) => _json('forbidden', 403)),
      );
      expect(
        () => client.complete(systemPrompt: 's', userPrompt: 'u'),
        throwsA(isA<LlmResponseException>()),
      );
    });
  });

  group('AiClientFactory', () {
    test('собирает клиента под каждого провайдера', () {
      final yandex = const AppSettings(
        aiEnabled: true,
        aiProvider: 'yandexGpt',
        aiApiKey: 'key',
        yandexFolderId: 'folder',
      );
      expect(AiClientFactory.build(yandex), isA<YandexGptClient>());
      expect(AiClientFactory.isConfigured(yandex), isTrue);

      final giga = const AppSettings(
        aiEnabled: true,
        aiProvider: 'gigaChat',
        gigaChatAuthKey: 'basic',
      );
      expect(AiClientFactory.build(giga), isA<GigaChatClient>());
      expect(AiClientFactory.isConfigured(giga), isTrue);

      final openai = const AppSettings(
        aiEnabled: true,
        aiApiKey: 'sk',
        aiBaseUrl: 'https://example.com/v1',
        aiModel: 'm',
      );
      expect(AiClientFactory.build(openai), isA<ChatCompletionClient>());
    });

    test('неполная конфигурация не считается готовой', () {
      expect(
        AiClientFactory.isConfigured(const AppSettings(
          aiEnabled: true,
          aiProvider: 'yandexGpt',
          aiApiKey: 'key',
        )),
        isFalse, // нет folderId
      );
      expect(
        AiClientFactory.isConfigured(const AppSettings(aiEnabled: false)),
        isFalse,
      );
    });

    test('неизвестное имя провайдера не валит фабрику', () {
      final s = const AppSettings(
        aiEnabled: true,
        aiProvider: 'mystery',
        aiApiKey: 'sk',
        aiBaseUrl: 'https://x/v1',
        aiModel: 'm',
      );
      expect(AiProvider.fromName(s.aiProvider), AiProvider.openaiCompatible);
      expect(AiClientFactory.isConfigured(s), isTrue);
    });
  });
}
