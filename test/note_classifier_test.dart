import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notes/features/notes/models/note_category.dart';
import 'package:smart_notes/features/notes/utils/note_classifier.dart';

void main() {
  group('NoteClassifier', () {
    test('рабочие формулировки -> work', () {
      expect(
        NoteClassifier.classify('Созвон по проекту, подготовить презентацию'),
        NoteCategory.work,
      );
      expect(NoteClassifier.classify('Сдать отчёт до дедлайна'), NoteCategory.work);
    });

    test('покупки -> shopping', () {
      expect(
        NoteClassifier.classify('Купить молоко и хлеб в магазине у дома'),
        NoteCategory.shopping,
      );
    });

    test('платежи -> finance', () {
      expect(
        NoteClassifier.classify('Оплатить счёт за интернет и кредит'),
        NoteCategory.finance,
      );
    });

    test('здоровье -> health', () {
      expect(
        NoteClassifier.classify('Визит к стоматологу, не забыть таблетки'),
        NoteCategory.health,
      );
    });

    test('семейные темы -> family', () {
      expect(
        NoteClassifier.classify('Забрать ребёнка из садика, позвонить маме'),
        NoteCategory.family,
      );
    });

    test('идеи -> idea', () {
      expect(
        NoteClassifier.classify('Идея для стартапа, гипотеза про подписки'),
        NoteCategory.idea,
      );
    });

    test('нейтральный текст без ключевых слов -> general', () {
      expect(NoteClassifier.classify('Просто заметка о разном'), NoteCategory.general);
    });

    test('несколько вхождений корня учитываются', () {
      final once = NoteClassifier.classify('купить воду');
      final twice = NoteClassifier.classify('купить хлеб, купить молоко, купить сыр');
      expect(once, NoteCategory.shopping);
      expect(twice, NoteCategory.shopping);
    });
  });
}
