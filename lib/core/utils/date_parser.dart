/// Распознавание дат и времени в русском тексте (естественный язык).
///
/// Поддерживаемые формулы (раздел 2.1 ТЗ):
///  * "завтра в 14:00", "сегодня", "послезавтра в 18:30"
///  * "в пятницу" / "в среду" (ближайший день недели, 09:00 по умолчанию)
///  * "через 3 часа", "через 40 минут", "через 2 дня", "через 1 час 30 минут"
///  * "10 декабря", "25 декабря 2025 в 10:00"
///  * "10.12.2025", "в полдень", "в полночь", "в 7 вечера", "в 9 утра"
///
/// Если время не указано — подставляется 09:00 (требование ТЗ).
library;

/// Подсвеченный фрагмент исходного текста (найденная дата/время).
class HighlightSpan {
  final int start;
  final int end;
  final String text;

  const HighlightSpan(this.start, this.end, this.text);
}

/// Результат разбора: момент напоминания (если найден) и span'ы для подсветки.
class DateParseResult {
  final DateTime? reminderDate;
  final List<HighlightSpan> spans;

  const DateParseResult(this.reminderDate, this.spans);

  static const empty = DateParseResult(null, <HighlightSpan>[]);
}

class NaturalDateParser {
  /// Точка отсчёта "сейчас" — инъектируется для тестов.
  final DateTime now;

  NaturalDateParser({DateTime? now}) : now = now ?? DateTime.now();

  static const Map<String, int> _months = {
    'января': 1, 'февраля': 2, 'марта': 3, 'апреля': 4, 'мая': 5, 'июня': 6,
    'июля': 7, 'августа': 8, 'сентября': 9, 'октября': 10, 'ноября': 11,
    'декабря': 12,
  };

  static const Map<String, int> _weekdays = {
    'понедельник': DateTime.monday, 'пн': DateTime.monday,
    'вторник': DateTime.tuesday, 'вт': DateTime.tuesday,
    'среду': DateTime.wednesday, 'среда': DateTime.wednesday, 'ср': DateTime.wednesday,
    'четверг': DateTime.thursday, 'чт': DateTime.thursday,
    'пятницу': DateTime.friday, 'пятница': DateTime.friday, 'пт': DateTime.friday,
    'субботу': DateTime.saturday, 'суббота': DateTime.saturday, 'сб': DateTime.saturday,
    'воскресенье': DateTime.sunday, 'вс': DateTime.sunday,
  };

  // ВАЖНО: в Dart \b — граница только для ASCII (\w = [A-Za-z0-9_]),
  // кириллица для него «не буква». Поэтому вокруг русских слов используем
  // явные границы через lookbehind/lookahead с кириллическими классами.
  static const String _notAfterWord = r'(?![а-яёА-ЯЁa-zA-Z0-9])';
  static const String _notBeforeWord = r'(?<![а-яёА-ЯЁa-zA-Z0-9])';

  static final RegExp _compoundDuration = RegExp(
    r'через\s+(\d+)\s*час\w*\s+(\d+)\s*минут\w*',
    caseSensitive: false,
  );
  static final RegExp _duration = RegExp(
    'через\\s+(\\d+)\\s*(час\\w*|ч|минут\\w*|мин|ден\\w*|дня|дней|д)$_notAfterWord',
    caseSensitive: false,
  );
  static final RegExp _keyword = RegExp(
    '$_notBeforeWord(послезавтра|завтра|сегодня)$_notAfterWord',
    caseSensitive: false,
  );
  static final RegExp _weekday = RegExp(
    '$_notBeforeWord(${_weekdays.keys.join('|')})$_notAfterWord',
    caseSensitive: false,
  );
  static final RegExp _textDate = RegExp(
    '(\\d{1,2})\\s+(${_months.keys.join('|')})(?:\\s+(\\d{4}))?',
    caseSensitive: false,
  );
  static final RegExp _numericDate = RegExp(
    '$_notBeforeWord(\\d{1,2})[./](\\d{1,2})(?:[./](\\d{2,4}))?$_notAfterWord',
  );
  static final RegExp _noon = RegExp(r'в\s+полдень', caseSensitive: false);
  static final RegExp _midnight = RegExp(r'в\s+полночь', caseSensitive: false);
  static final RegExp _colonTime = RegExp(r'(\d{1,2}):(\d{2})');
  static final RegExp _spokenTime = RegExp(
    r'в\s+(\d{1,2})(?:[.:](\d{2}))?\s*(утра|дня|вечера|ночи)?',
    caseSensitive: false,
  );

  DateParseResult parse(String input) {
    final lower = input.toLowerCase();
    final spans = <HighlightSpan>[];
    final consumed = <_Range>[];
    DateTime? base; // дата в 00:00
    _Time? time;
    DateTime? relative; // абсолютный момент для "через ..."
    var isMidnight = false; // "в полночь" без даты -> наступающая полночь

    bool overlaps(int start, int end) =>
        consumed.any((r) => start < r.end && end > r.start);

    void claim(Match m) {
      if (!overlaps(m.start, m.end)) {
        consumed.add(_Range(m.start, m.end));
        spans.add(HighlightSpan(m.start, m.end, input.substring(m.start, m.end)));
      }
    }

    // 1. Относительные длительности ("через ...")
    final compound = _compoundDuration.firstMatch(lower);
    if (compound != null) {
      relative = now.add(Duration(
        hours: int.parse(compound.group(1)!),
        minutes: int.parse(compound.group(2)!),
      ));
      claim(compound);
    }
    for (final m in _duration.allMatches(lower)) {
      if (overlaps(m.start, m.end)) continue;
      final n = int.parse(m.group(1)!);
      final unit = m.group(2)!.toLowerCase();
      if (unit.startsWith('ч')) {
        relative = now.add(Duration(hours: n));
      } else if (unit.startsWith('м')) {
        relative = now.add(Duration(minutes: n));
      } else {
        relative = now.add(Duration(days: n));
      }
      claim(m);
    }

    // 2. сегодня / завтра / послезавтра
    final kw = _keyword.firstMatch(lower);
    if (kw != null) {
      const shift = {'сегодня': 0, 'завтра': 1, 'послезавтра': 2};
      base = _dateOnly(now.add(Duration(days: shift[kw.group(1)!]!)));
      claim(kw);
    }

    // 3. День недели — ближайший наступающий (не сегодня)
    if (base == null) {
      final wd = _weekday.firstMatch(lower);
      if (wd != null) {
        final target = _weekdays[wd.group(1)!.toLowerCase()]!;
        var diff = target - now.weekday;
        if (diff <= 0) diff += 7;
        base = _dateOnly(now.add(Duration(days: diff)));
        claim(wd);
      }
    }

    // 4. Число + месяц текстом
    if (base == null) {
      final td = _textDate.firstMatch(lower);
      if (td != null) {
        final day = int.parse(td.group(1)!);
        final month = _months[td.group(2)!.toLowerCase()]!;
        var year = td.group(3) != null ? int.parse(td.group(3)!) : now.year;
        var cand = DateTime(year, month, day);
        if (cand.isBefore(_dateOnly(now))) {
          year += 1;
          cand = DateTime(year, month, day);
        }
        base = cand;
        claim(td);
      }
    }

    // 5. Числовая дата дд.мм[.гггг]
    if (base == null) {
      final nd = _numericDate.firstMatch(lower);
      if (nd != null) {
        final day = int.parse(nd.group(1)!);
        final month = int.parse(nd.group(2)!);
        if (day >= 1 && day <= 31 && month >= 1 && month <= 12) {
          var year = nd.group(3) != null ? int.parse(nd.group(3)!) : now.year;
          if (year < 100) year += 2000;
          var cand = DateTime(year, month, day);
          if (cand.isBefore(_dateOnly(now))) {
            year += 1;
            cand = DateTime(year, month, day);
          }
          base = cand;
          claim(nd);
        }
      }
    }

    // 6. Время
    final noon = _noon.firstMatch(lower);
    if (noon != null && !overlaps(noon.start, noon.end)) {
      time = const _Time(12, 0);
      claim(noon);
    }
    final midnight = _midnight.firstMatch(lower);
    if (midnight != null && !overlaps(midnight.start, midnight.end)) {
      time = const _Time(0, 0);
      isMidnight = true;
      claim(midnight);
    }
    if (time == null) {
      final ct = _colonTime.firstMatch(lower);
      if (ct != null && !overlaps(ct.start, ct.end)) {
        final hour = int.parse(ct.group(1)!);
        final minute = int.parse(ct.group(2)!);
        if (hour <= 23 && minute <= 59) {
          time = _Time(hour, minute);
          claim(ct);
        }
      }
    }
    if (time == null) {
      final st = _spokenTime.firstMatch(lower);
      if (st != null && !overlaps(st.start, st.end)) {
        final hour = _adjustHour(int.parse(st.group(1)!), st.group(3)?.toLowerCase());
        time = _Time(hour, int.parse(st.group(2) ?? '0'));
        claim(st);
      }
    }

    DateTime? reminder;
    if (relative != null) {
      reminder = DateTime(relative.year, relative.month, relative.day,
          relative.hour, relative.minute);
    } else if (base != null) {
      final t = time ?? const _Time(9, 0); // дефолт 09:00 по ТЗ
      reminder = DateTime(base.year, base.month, base.day, t.hour, t.minute);
    } else if (time != null) {
      if (isMidnight) {
        // "в полночь" без указания даты — это 00:00 следующего дня.
        final tomorrow = _dateOnly(now).add(const Duration(days: 1));
        reminder = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 0, 0);
      } else {
        reminder =
            DateTime(now.year, now.month, now.day, time.hour, time.minute);
      }
    }

    return DateParseResult(reminder, spans);
  }

  /// Упрощённый вызов: только момент напоминания.
  DateTime? parseReminder(String input) => parse(input).reminderDate;

  static int _adjustHour(int hour, String? word) {
    if (word == null) return hour;
    switch (word) {
      case 'утра':
        return hour == 12 ? 0 : hour;
      case 'дня':
      case 'вечера':
        return hour < 12 ? hour + 12 : hour;
      case 'ночи':
        return (hour >= 7 && hour < 12) ? hour + 12 : hour;
      default:
        return hour;
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

class _Range {
  final int start;
  final int end;
  const _Range(this.start, this.end);
}

class _Time {
  final int hour;
  final int minute;
  const _Time(this.hour, this.minute);
}
