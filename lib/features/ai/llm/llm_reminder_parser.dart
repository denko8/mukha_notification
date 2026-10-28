import 'dart:convert';

import '../../notes/models/note_category.dart';
import '../ai_reminder_parser.dart';
import '../models/ai_parse_result.dart';
import '../rule_based_ai_parser.dart';
import 'chat_completion_client.dart';

/// Облачный разбор заметки через LLM.
///
/// Модель возвращает строгий JSON; любая ошибка (сеть, формат, мусор в
/// дате) молча откатывается на детерминированные правила, поэтому
/// пользователь никогда не теряет возможность создать заметку.
class LlmReminderParser implements AiReminderParser {
  final ChatCompletionClient client;
  final AiReminderParser fallback;

  LlmReminderParser({required this.client, this.fallback = const RuleBasedAiParser()});

  static const _systemPrompt = '''
Ты — помощник напоминаний в приложении Smart Notes. Пользователь пишет
заметку на русском в свободной форме. Извлеки из неё структуру и верни
ТОЛЬКО валидный JSON без markdown и пояснений, со схемой:
{
  "reminderAt": "ISO-8601 дата и время в локальной таймзоне пользователя либо null",
  "category": одно из: general, work, shopping, finance, health, family, idea,
  "summary": "краткая суть заметки 1 предложением",
  "confidence": число от 0 до 1
}
Правила:
- если явного намерения напомнить нет, reminderAt = null;
- относительные даты считай от переданного пользователем "сейчас";
- "к обеду" = 13:00, "после обеда" = 14:00, "утром" = 09:00,
  "вечером" = 19:00, "к ужину" = 20:00, "ночью" = 23:00;
- если время не указано, но дата есть — используй 09:00;
- категорию выбирай по смыслу, при неоднозначности — general.''';

  @override
  Future<AiParseResult> parse(String text, {DateTime? now}) async {
    final referenceNow = now ?? DateTime.now();
    final ruleResult = await fallback.parse(text, now: referenceNow);

    try {
      final raw = await client.complete(
        systemPrompt: _systemPrompt,
        userPrompt:
            'Сейчас: ${referenceNow.toIso8601String()}\nЗаметка: $text',
      );
      final map = _decodeJson(raw);
      final reminder = _parseDate(map['reminderAt']);
      final category = _parseCategory(map['category']);
      final summary = map['summary'] is String ? map['summary'] as String : null;
      final confidence = (map['confidence'] is num)
          ? (map['confidence'] as num).toDouble().clamp(0.0, 1.0)
          : 0.5;

      return AiParseResult(
        // Подсветку всегда считаем локально — UI не зависит от модели.
        reminderDate: reminder ?? ruleResult.reminderDate,
        category: category,
        summary: summary,
        confidence: confidence.toDouble(),
        fromLlm: true,
        spans: ruleResult.spans,
      );
    } catch (_) {
      // Сеть/формат/таймаут — пользователь работает на правилах.
      return ruleResult;
    }
  }

  Map<String, dynamic> _decodeJson(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'^```(?:json)?'), '')
        .replaceAll(RegExp(r'```$'), '')
        .trim();
    final decoded = json.decode(cleaned);
    if (decoded is! Map<String, dynamic>) {
      throw LlmResponseException('JSON — не объект');
    }
    return decoded;
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    // Отвергаем заведомо бессмысленные даты.
    if (parsed.year < 2000 || parsed.year > 2100) return null;
    return parsed;
  }

  NoteCategory _parseCategory(Object? value) {
    if (value is! String) return NoteCategory.general;
    return NoteCategory.values.firstWhere(
      (c) => c.name == value.toLowerCase().trim(),
      orElse: () => NoteCategory.general,
    );
  }
}
