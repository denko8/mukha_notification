import 'package:url_launcher/url_launcher.dart';

/// Добавление события в календарь (P3 ТЗ).
///
/// Кроссплатформенный путь без нативных разрешений: предзаполненная
/// форма Google Calendar открывается в браузере/приложении. На Android
/// пользователь может выбрать системный календарь из той же формы.
class CalendarService {
  CalendarService._();

  static Future<bool> addEvent({
    required String title,
    required DateTime start,
    DateTime? end,
    String? notes,
  }) async {
    final endTime = end ?? start.add(const Duration(hours: 1));
    final uri = Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': title,
      'dates': '${_fmt(start)}/${_fmt(endTime)}',
      if (notes != null && notes.isNotEmpty) 'details': notes,
    });
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String _fmt(DateTime d) =>
      d.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first + 'Z';
}
