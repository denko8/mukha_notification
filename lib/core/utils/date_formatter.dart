import 'package:intl/intl.dart';

/// Человекочитаемые даты в русской локали.
class DateFormatter {
  DateFormatter._();

  static final _dayMonth = DateFormat('d MMM', 'ru');
  static final _dayMonthTime = DateFormat('d MMM, HH:mm', 'ru');
  static final _full = DateFormat('d MMMM yyyy, HH:mm', 'ru');
  static final _history = DateFormat('d MMM в HH:mm', 'ru');
  static final _time = DateFormat('HH:mm');

  /// "Завтра в 14:00" / "Сегодня в 09:00" / "10 дек, 14:00".
  static String reminder(DateTime date, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final that = DateTime(date.year, date.month, date.day);
    final diff = that.difference(today).inDays;
    final time = _time.format(date);

    if (diff == 0) return 'Сегодня в $time';
    if (diff == 1) return 'Завтра в $time';
    if (diff == 2) return 'Послезавтра в $time';
    return _dayMonthTime.format(date);
  }

  static String full(DateTime date) => _full.format(date);

  static String history(DateTime date) => _history.format(date);

  static String dayMonth(DateTime date) => _dayMonth.format(date);

  static String timeOnly(DateTime date) => _time.format(date);
}
