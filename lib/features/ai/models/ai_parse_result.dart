import '../../../core/utils/date_parser.dart';
import '../../notes/models/note_category.dart' show CategoryKeys;

/// Результат «умного» разбора заметки.
/// Не зависит от источника: правила, облачная LLM или on-device модель.
class AiParseResult {
  /// Предложенное время напоминания (null — напоминание не нужно).
  final DateTime? reminderDate;

  /// Предложенная категория: ключ встроенной (`work`, …) или
  /// пользовательской (`custom:<uuid>`).
  final String categoryKey;

  /// Краткая выжимка сути заметки (LLM может переформулировать).
  final String? summary;

  /// Уверенность 0..1. У правил она дискретная, у LLM — из ответа.
  final double confidence;

  /// true, если результат пришёл от нейросети, а не от правил.
  final bool fromLlm;

  /// Диапазоны для золотистой подсветки (всегда считаются локально,
  /// чтобы UI не зависел от доступности модели).
  final List<HighlightSpan> spans;

  const AiParseResult({
    this.reminderDate,
    this.categoryKey = CategoryKeys.general,
    this.summary,
    this.confidence = 0,
    this.fromLlm = false,
    this.spans = const [],
  });

  static const empty = AiParseResult();
}
