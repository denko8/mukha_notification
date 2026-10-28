import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notes/features/notes/models/custom_category.dart';
import 'package:smart_notes/features/notes/models/note_category.dart';
import 'package:smart_notes/features/notes/utils/note_classifier.dart';

void main() {
  group('NoteClassifier — встроенные категории', () {
    test('рабочие формулировки -> work', () {
      expect(
        NoteClassifier.classifyKey(
            'Созвон по проекту, подготовить презентацию', const []),
        NoteCategory.work.name,
      );
      expect(
        NoteClassifier.classifyKey('Сдать отчёт до дедлайна', const []),
        NoteCategory.work.name,
      );
    });

    test('покупки -> shopping', () {
      expect(
        NoteClassifier.classifyKey(
            'Купить молоко и хлеб в магазине у дома', const []),
        NoteCategory.shopping.name,
      );
    });

    test('платежи -> finance', () {
      expect(
        NoteClassifier.classifyKey('Оплатить счёт за интернет и кредит', const []),
        NoteCategory.finance.name,
      );
    });

    test('здоровье -> health', () {
      expect(
        NoteClassifier.classifyKey(
            'Визит к стоматологу, не забыть таблетки', const []),
        NoteCategory.health.name,
      );
    });

    test('семейные темы -> family', () {
      expect(
        NoteClassifier.classifyKey(
            'Забрать ребёнка из садика, позвонить маме', const []),
        NoteCategory.family.name,
      );
    });

    test('идеи -> idea', () {
      expect(
        NoteClassifier.classifyKey(
            'Идея для стартапа, гипотеза про подписки', const []),
        NoteCategory.idea.name,
      );
    });

    test('нейтральный текст без ключевых слов -> general', () {
      expect(
        NoteClassifier.classifyKey('Просто заметка о разном', const []),
        NoteCategory.general.name,
      );
    });

    test('несколько вхождений корня учитываются', () {
      final once = NoteClassifier.classifyKey('купить воду', const []);
      final twice = NoteClassifier.classifyKey(
          'купить хлеб, купить молоко, купить сыр', const []);
      expect(once, NoteCategory.shopping.name);
      expect(twice, NoteCategory.shopping.name);
    });
  });

  group('NoteClassifier — пользовательские категории', () {
    const fishing = CustomCategory(
      id: 'fishing-id',
      label: 'Рыбалка',
      keywords: ['рыбалк', 'спиннинг'],
    );
    const car = CustomCategory(id: 'car-id', label: 'Машина', keywords: ['ремонт']);

    test('слово пользователя уводит заметку в его категорию', () {
      expect(
        NoteClassifier.classifyKey('Взять спиннинг на выходные', const [fishing]),
        CategoryKeys.forCustom('fishing-id'),
      );
      expect(
        NoteClassifier.classifyKey(
            'Записаться на ремонт коробки', const [car]),
        CategoryKeys.forCustom('car-id'),
      );
    });

    test('без своих слов работает обычный словарь', () {
      expect(
        NoteClassifier.classifyKey('Купить молоко', const [fishing, car]),
        NoteCategory.shopping.name,
      );
    });

    test('нейтральный текст с пользовательскими категориями -> general', () {
      expect(
        NoteClassifier.classifyKey('Просто мысли ни о чём', const [fishing]),
        NoteCategory.general.name,
      );
    });

    test('пустые ключевые слова игнорируются', () {
      const empty = CustomCategory(id: 'x', label: 'Пусто', keywords: ['', '  ']);
      expect(
        NoteClassifier.classifyKey('случайный текст', const [empty]),
        NoteCategory.general.name,
      );
    });
  });
}
