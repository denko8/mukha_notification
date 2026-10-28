/// Готовые шаблоны заметок (P3 ТЗ).
class NoteTemplate {
  final String title;
  final String text;

  const NoteTemplate(this.title, this.text);
}

class NoteTemplates {
  NoteTemplates._();

  static const List<NoteTemplate> all = [
    NoteTemplate(
      'Список покупок',
      'Купить: молоко, хлеб, яйца, овощи. Зайти в магазин сегодня после работы',
    ),
    NoteTemplate(
      'Встреча',
      'Встреча с командой завтра в 14:00, обсудить дедлайн проекта',
    ),
    NoteTemplate(
      'Визит к врачу',
      'Визит к врачу в пятницу в 10:00, взять результаты анализов',
    ),
    NoteTemplate(
      'Оплата счёта',
      'Оплатить счёт за коммуналку до 25 числа',
    ),
    NoteTemplate(
      'Идея',
      'Идея: записать мысль и проработать гипотезу на выходных',
    ),
    NoteTemplate(
      'День рождения',
      'День рождения: выбрать подарок и заказать столик заранее',
    ),
  ];
}
