import '../../core/utils/date_parser.dart';
import '../notes/models/custom_category.dart';
import '../notes/utils/note_classifier.dart';
import 'ai_reminder_parser.dart';
import 'models/ai_parse_result.dart';

/// Базовый офлайн-уровень: детерминированный regex-парсер + словарный
/// классификатор. Всегда доступен, ничего не стоит, не требует сети.
/// Используется и как самостоятельный парсер, и как фолбэк для LLM.
class RuleBasedAiParser implements AiReminderParser {
  /// Пользовательские категории со словами для офлайн-распознавания.
  final List<CustomCategory> customCategories;

  const RuleBasedAiParser({this.customCategories = const []});

  @override
  Future<AiParseResult> parse(String text, {DateTime? now}) async {
    final parser = NaturalDateParser(now: now);
    final dateResult = parser.parse(text);
    final categoryKey = NoteClassifier.classifyKey(text, customCategories);

    return AiParseResult(
      reminderDate: dateResult.reminderDate,
      categoryKey: categoryKey,
      confidence: dateResult.reminderDate == null ? 0.3 : 0.8,
      fromLlm: false,
      spans: dateResult.spans,
    );
  }
}
