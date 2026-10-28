import 'models/ai_parse_result.dart';

/// «Умный» разбор заметки: извлечение времени напоминания, категории,
/// выжимки. Реализации: правила, облачная LLM, on-device модель.
///
/// Контракт обязан никогда не бросать исключение наружу: при сбое
/// нейросети реализация возвращает результат фолбэка на правилах.
abstract class AiReminderParser {
  Future<AiParseResult> parse(String text, {DateTime? now});
}
