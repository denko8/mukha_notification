import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notes/core/utils/date_parser.dart';

void main() {
  // Зафиксированное "сейчас": четверг, 5 декабря 2024, 10:00.
  final now = DateTime(2024, 12, 5, 10, 0);
  NaturalDateParser parser() => NaturalDateParser(now: now);

  group('NaturalDateParser — примеры из ТЗ', () {
    test('"завтра в 14:00" -> следующий день 14:00', () {
      expect(
        parser().parseReminder('Позвонить Диме завтра в 14:00'),
        DateTime(2024, 12, 6, 14, 0),
      );
    });

    test('"в пятницу" -> ближайшая пятница, 09:00 по умолчанию', () {
      expect(
        parser().parseReminder('Встреча в пятницу'),
        DateTime(2024, 12, 6, 9, 0),
      );
    });

    test('"через 3 часа" -> текущее время + 3 часа', () {
      expect(
        parser().parseReminder('Заплатить через 3 часа'),
        DateTime(2024, 12, 5, 13, 0),
      );
    });

    test('"10 декабря" -> 10 декабря текущего года, 09:00', () {
      expect(
        parser().parseReminder('Визит 10 декабря'),
        DateTime(2024, 12, 10, 9, 0),
      );
    });
  });

  group('NaturalDateParser — расширенные формулировки', () {
    test('послезавтра с временем', () {
      expect(
        parser().parseReminder('Отчёт послезавтра в 18:30'),
        DateTime(2024, 12, 7, 18, 30),
      );
    });

    test('день недели в падеже ("в среду") -> следующая среда', () {
      expect(
        parser().parseReminder('Врач в среду'),
        DateTime(2024, 12, 11, 9, 0),
      );
    });

    test('числовая дата с годом', () {
      expect(
        parser().parseReminder('Дедлайн 10.12.2025'),
        DateTime(2025, 12, 10, 9, 0),
      );
    });

    test('полдень и полночь', () {
      expect(parser().parseReminder('Обед в полдень'), DateTime(2024, 12, 5, 12, 0));
      expect(parser().parseReminder('Созвон в полночь'), DateTime(2024, 12, 6, 0, 0));
    });

    test('разговорное время "в 7 вечера" и "в 9 утра"', () {
      expect(parser().parseReminder('Кино в 7 вечера'), DateTime(2024, 12, 5, 19, 0));
      expect(parser().parseReminder('Позвонить в 9 утра'), DateTime(2024, 12, 5, 9, 0));
    });

    test('составная длительность "через 1 час 30 минут"', () {
      expect(
        parser().parseReminder('Через 1 час 30 минут позвонить'),
        DateTime(2024, 12, 5, 11, 30),
      );
    });

    test('относительные минуты и дни', () {
      expect(parser().parseReminder('через 40 минут'), DateTime(2024, 12, 5, 10, 40));
      expect(parser().parseReminder('через 2 дня'), DateTime(2024, 12, 7, 10, 0));
    });

    test('русские окончания не ломают длительности (регрессия на ASCII \\w)', () {
      expect(parser().parseReminder('через 1 час'), DateTime(2024, 12, 5, 11, 0));
      expect(parser().parseReminder('через 3 часа'), DateTime(2024, 12, 5, 13, 0));
      expect(parser().parseReminder('через 30 мин'), DateTime(2024, 12, 5, 10, 30));
      expect(parser().parseReminder('через 7 дней'), DateTime(2024, 12, 12, 10, 0));
      expect(
        parser().parseReminder('через 2 часа 15 минут'),
        DateTime(2024, 12, 5, 12, 15),
      );
    });

    test('число и месяц текстом со временем', () {
      expect(
        parser().parseReminder('25 декабря в 10:00 встреча'),
        DateTime(2024, 12, 25, 10, 0),
      );
    });

    test('прошедшая дата без года переносится на следующий год', () {
      // 1 января уже прошло -> 2025 год
      expect(parser().parseReminder('1 января'), DateTime(2025, 1, 1, 9, 0));
    });

    test('текст без даты -> null', () {
      final result = parser().parse('Просто заметка без даты');
      expect(result.reminderDate, isNull);
      expect(result.spans, isEmpty);
    });
  });

  group('NaturalDateParser — кириллические границы слов (регрессия на \\b)', () {
    test('"завтра" внутри слова "завтраки" не распознаётся как дата', () {
      // Ключевое слово является частью другого слова -> даты нет.
      final result = parser().parse('Купить завтраки в магазине');
      expect(result.reminderDate, isNull);
      expect(result.spans, isEmpty);
    });

    test('"пятницу" внутри более длинного слова не ловим', () {
      final result = parser().parse('пятничную встречу перенести');
      expect(result.reminderDate, isNull);
    });

    test('границы не мешают обычным формулировкам', () {
      expect(
        parser().parseReminder('позвонить завтра'),
        DateTime(2024, 12, 6, 9, 0),
      );
      expect(
        parser().parseReminder('через 5 минут выйти'),
        DateTime(2024, 12, 5, 10, 5),
      );
    });
  });

  group('NaturalDateParser — подсветка', () {
    test('возвращает span-ы найденных фрагментов', () {
      final result = parser().parse('завтра в 14:00');
      expect(result.reminderDate, DateTime(2024, 12, 6, 14, 0));
      expect(result.spans, isNotEmpty);
      final texts = result.spans.map((s) => s.text).join('|');
      expect(texts, contains('завтра'));
      expect(texts, contains('14:00'));
    });

    test('span-ы ссылаются на корректные диапазоны исходного текста', () {
      const input = 'Встреча в пятницу';
      final result = parser().parse(input);
      final span = result.spans.first;
      expect(input.substring(span.start, span.end), span.text);
    });
  });
}
