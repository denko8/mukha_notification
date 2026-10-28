import '../../core/utils/date_parser.dart';
import '../notes/utils/note_classifier.dart';
import 'ai_reminder_parser.dart';
import 'models/ai_parse_result.dart';

/// Базовый офлайн-уровень: детерминированный regex-парсер + словарный
/// классификатор. Всегда доступен, ничего не стоит, не требует сети.
/// Используется и как самостоятельный парсер, и как фолбэк для LLM.
class RuleBasedAiParser implements AiReminderParser {
  const RuleBasedAiParser();

  @override
  Future<AiParseResult> parse(String text, {DateTime? now}) async {
    final parser = NaturalDateParser(now: now);
    final dateResult = parser.parse(text);
    final category = NoteClassifier.classify(text);

    return AiParseResult(
      reminderDate: dateResult.reminderDate,
      category: category,
      confidence: dateResult.reminderDate == null ? 0.3 : 0.8,
      fromLlm: false,
      spans: dateResult.spans,
    );
  }
}
