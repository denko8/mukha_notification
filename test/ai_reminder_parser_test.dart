import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notes/features/ai/llm/chat_completion_client.dart';
import 'package:smart_notes/features/ai/llm/llm_reminder_parser.dart';
import 'package:smart_notes/features/ai/models/ai_parse_result.dart';
import 'package:smart_notes/features/ai/rule_based_ai_parser.dart';
import 'package:smart_notes/features/notes/models/custom_category.dart';
import 'package:smart_notes/features/notes/models/note_category.dart';

class _FakeChatClient implements ChatCompletionClient {
  final String? response;
  final Object? error;
  String? lastSystemPrompt;
  String? lastUserPrompt;

  _FakeChatClient({this.response, this.error});

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    lastSystemPrompt = systemPrompt;
    lastUserPrompt = userPrompt;
    if (error != null) throw error!;
    return response!;
  }
}

void main() {
  final now = DateTime(2024, 12, 5, 10, 0);

  group('RuleBasedAiParser', () {
    test('извлекает дату правилами и категорию словарём', () async {
      const parser = RuleBasedAiParser();
      final result = await parser.parse('Оплатить счёт завтра в 14:00', now: now);
      expect(result.fromLlm, isFalse);
      expect(result.reminderDate, DateTime(2024, 12, 6, 14, 0));
      expect(result.categoryKey, NoteCategory.finance.name);
      expect(result.spans, isNotEmpty);
    });

    test('без даты возвращает null и низкую уверенность', () async {
      const parser = RuleBasedAiParser();
      final result = await parser.parse('Просто мысли о разном', now: now);
      expect(result.reminderDate, isNull);
      expect(result.confidence, lessThan(0.5));
    });

    test('пользовательская категория опознаётся по её словам офлайн', () async {
      const parser = RuleBasedAiParser(
        customCategories: [
          CustomCategory(id: 'fish', label: 'Рыбалка', keywords: ['спиннинг']),
        ],
      );
      final result = await parser.parse('Собрать спиннинг к выходным', now: now);
      expect(result.categoryKey, CategoryKeys.forCustom('fish'));
      expect(result.fromLlm, isFalse);
    });
  });

  group('LlmReminderParser', () {
    test('успешный JSON модели: дата, категория, выжимка', () async {
      final client = _FakeChatClient(
        response: '''
        {
          "reminderAt": "2024-12-06T13:00:00",
          "category": "family",
          "summary": "Забрать ребёнка из садика к обеду",
          "confidence": 0.94
        }''',
      );
      final parser = LlmReminderParser(client: client);
      final AiParseResult result =
          await parser.parse('завтра надо забрать мелкого из садика к обеду', now: now);

      expect(result.fromLlm, isTrue);
      expect(result.reminderDate, DateTime(2024, 12, 6, 13, 0));
      expect(result.categoryKey, NoteCategory.family.name);
      expect(result.summary, contains('садика'));
      expect(result.confidence, closeTo(0.94, 0.001));
      // Подсветка всё равно локальная.
      expect(client.lastSystemPrompt, contains('Smart Notes'));
      expect(client.lastUserPrompt, contains('2024-12-05'));
    });

    test('модель в markdown-обёртке ```json тоже парсится', () async {
      final client = _FakeChatClient(
        response: '```json\n{"reminderAt":null,"category":"idea",'
            '"summary":"идея","confidence":0.6}\n```',
      );
      final result = await LlmReminderParser(client: client)
          .parse('идея для стартапа', now: now);
      expect(result.fromLlm, isTrue);
      expect(result.reminderDate, isNull);
      expect(result.categoryKey, NoteCategory.idea.name);
    });

    test('сеть упала — тихий откат на правила', () async {
      final client = _FakeChatClient(error: LlmResponseException('timeout'));
      final result = await LlmReminderParser(client: client)
          .parse('Встреча завтра в 14:00', now: now);
      expect(result.fromLlm, isFalse);
      expect(result.reminderDate, DateTime(2024, 12, 6, 14, 0));
    });

    test('мусорный JSON — откат на правила', () async {
      final client = _FakeChatClient(response: 'это не json вообще');
      final result = await LlmReminderParser(client: client)
          .parse('Встреча завтра в 14:00', now: now);
      expect(result.fromLlm, isFalse);
      expect(result.reminderDate, DateTime(2024, 12, 6, 14, 0));
    });

    test('некорректная дата модели заменяется датой правил', () async {
      final client = _FakeChatClient(
        response: '{"reminderAt":"1800-01-01T00:00:00",'
            '"category":"work","summary":"x","confidence":0.5}',
      );
      final result = await LlmReminderParser(client: client)
          .parse('Встреча завтра в 14:00', now: now);
      expect(result.fromLlm, isTrue);
      // Дата модели отвергнута, взят результат правил.
      expect(result.reminderDate, DateTime(2024, 12, 6, 14, 0));
    });

    test('неизвестная категория заменяется категорией правил', () async {
      final client = _FakeChatClient(
        response: '{"reminderAt":null,"category":"space_travel",'
            '"summary":"x","confidence":0.2}',
      );
      final result = await LlmReminderParser(client: client)
          .parse('полететь на марс', now: now);
      // Правилу зацепиться не за что -> «Общее».
      expect(result.categoryKey, NoteCategory.general.name);
    });

    test('confidence зажимается в диапазон 0..1', () async {
      final client = _FakeChatClient(
        response: '{"reminderAt":null,"category":"general",'
            '"summary":"x","confidence":7.5}',
      );
      final result = await LlmReminderParser(client: client)
          .parse('обычная заметка', now: now);
      expect(result.confidence, 1.0);
    });

    test('пользовательская категория приходит из модели по её ключу', () async {
      const customKey = 'custom:fish';
      final client = _FakeChatClient(
        response: '{"reminderAt":null,"category":"$customKey",'
            '"summary":"рыбалка","confidence":0.8}',
      );
      final parser = LlmReminderParser(
        client: client,
        customCategories: const [
          CustomCategory(id: 'fish', label: 'Рыбалка', keywords: ['рыбалк']),
        ],
      );
      final result = await parser.parse('купить червей для рыбалки', now: now);
      expect(result.categoryKey, customKey);
      // Промпт содержит и ключ, и название пользовательской категории.
      expect(client.lastSystemPrompt, contains(customKey));
      expect(client.lastSystemPrompt, contains('Рыбалка'));
    });

    test('модель вернула название вместо ключа — каталог сопоставит его', () async {
      final client = _FakeChatClient(
        response: '{"reminderAt":null,"category":"Рыбалка",'
            '"summary":"рыбалка","confidence":0.7}',
      );
      final parser = LlmReminderParser(
        client: client,
        customCategories: const [
          CustomCategory(id: 'fish', label: 'Рыбалка', keywords: []),
        ],
      );
      final result = await parser.parse('поехать на озеро', now: now);
      expect(result.categoryKey, CategoryKeys.forCustom('fish'));
    });
  });
}
