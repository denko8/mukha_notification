/// Пользовательская категория заметки.
///
/// В отличие от встроенных [NoteCategory], хранится в настройках как данные.
/// [keywords] — слова/основы для офлайн-классификатора: если они встречаются
/// в тексте, заметка автоматически попадёт в эту категорию без всякой сети.
/// Облачный LLM дополнительно опознаёт категорию по её [label].
class CustomCategory {
  /// Стабильный идентификатор (uuid v4); в заметки попадает как
  /// `custom:<id>` — см. [CategoryKeys.forCustom].
  final String id;

  /// Отображаемое название, уникальное в пределах всех категорий.
  final String label;

  /// Ключевые слова для локального распознавания (нижний регистр,
  /// могут быть основами: «рыбалк», «ремонт»).
  final List<String> keywords;

  const CustomCategory({
    required this.id,
    required this.label,
    this.keywords = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'keywords': keywords,
      };

  factory CustomCategory.fromMap(Map<String, dynamic> map) => CustomCategory(
        id: map['id'] as String,
        label: map['label'] as String? ?? '',
        keywords: (map['keywords'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  CustomCategory copyWith({String? label, List<String>? keywords}) =>
      CustomCategory(
        id: id,
        label: label ?? this.label,
        keywords: keywords ?? this.keywords,
      );
}
