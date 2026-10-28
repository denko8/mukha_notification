import '../models/note_category.dart';

/// Локальная ИИ-классификация типа заметки (P3 ТЗ).
///
/// Без внешних API и приватных данных в облаке: взвешенный словарь
/// ключевых слов на русском. Категория с максимальным весом побеждает,
/// при равенстве/нуле — [NoteCategory.general].
class NoteClassifier {
  const NoteClassifier._();

  static const Map<NoteCategory, Map<String, int>> _vocabulary = {
    NoteCategory.work: {
      'встреча': 3, 'совещание': 3, 'отчёт': 3, 'отчет': 3, 'дедлайн': 3,
      'проект': 2, 'задача': 2, 'релиз': 2, 'клиент': 2, 'презентация': 3,
      'почта': 1, 'email': 2, 'работ': 1, 'командировк': 2, 'созвон': 3,
      'спринт': 2, 'таск': 2,
    },
    NoteCategory.shopping: {
      'купить': 3, 'куплю': 2, 'магазин': 2, 'продукт': 2, 'молоко': 3,
      'хлеб': 3, 'заказ': 1, 'маркет': 2, 'корзин': 1, 'скидк': 1,
      'аптек': 2,
    },
    NoteCategory.finance: {
      'оплатить': 3, 'оплата': 3, 'счёт': 3, 'счет': 3, 'платёж': 3,
      'платеж': 3, 'кредит': 3, 'ипотек': 3, 'налог': 3, 'долг': 2,
      'зарплат': 2, 'бюджет': 2, 'подписк': 2, 'квитанц': 3, 'банк': 2,
      'перевод': 1,
    },
    NoteCategory.health: {
      'врач': 3, 'больниц': 3, 'таблетк': 3, 'лекарств': 3, 'анализ': 2,
      'тренировк': 2, 'зал': 1, 'прививк': 3, 'стоматолог': 3, 'диет': 2,
      'давление': 2, 'приём': 2, 'прием': 2, 'здоров': 2,
    },
    NoteCategory.family: {
      'мам': 2, 'пап': 2, 'ребёнок': 3, 'ребенок': 3, 'детей': 2, 'садик': 3,
      'школ': 2, 'родител': 2, 'семь': 2, 'ужин': 1, 'день рождения': 2,
      'свадьб': 2,
    },
    NoteCategory.idea: {
      'идея': 3, 'придумать': 2, 'замысел': 3, 'гипотез': 3, 'прототип': 2,
      'стартап': 2, 'вдохнов': 2, 'набросать': 1,
    },
  };

  static NoteCategory classify(String text) {
    final lower = text.toLowerCase();
    final scores = <NoteCategory, int>{
      for (final c in NoteCategory.values) c: 0,
    };

    _vocabulary.forEach((category, words) {
      words.forEach((stem, weight) {
        var pos = lower.indexOf(stem);
        while (pos != -1) {
          scores[category] = scores[category]! + weight;
          pos = lower.indexOf(stem, pos + stem.length);
        }
      });
    });

    NoteCategory best = NoteCategory.general;
    var bestScore = 0;
    scores.forEach((category, score) {
      if (score > bestScore) {
        bestScore = score;
        best = category;
      }
    });
    return best;
  }
}
