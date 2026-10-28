import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Абстракция над доставкой напоминаний.
/// Сегодня — локальные уведомления, завтра — FCM (раздел 3.1 ТЗ)
/// подключается второй реализацией без правок экранов.
abstract class NotificationService {
  Future<void> init();

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  });

  Future<void> cancel(int id);

  Future<void> cancelAll();
}

class LocalNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  @override
  Future<void> init() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    try {
      // В flutter_timezone 3.x метод статический.
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Если системную зону определить не удалось — остаёмся на UTC.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Android 13+: запрос разрешения на уведомления.
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    // Android 12+: право на точные будильники. На части прошивок
    // (vivo/OPPO/Xiaomi) выдаётся через системный экран настроек.
    await androidPlugin?.requestExactAlarmsPermission();
    _ready = true;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!_ready) await init();
    // Напоминание на прошедшее время не планируем.
    if (!when.isAfter(DateTime.now())) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'smart_notes_reminders',
        'Напоминания',
        channelDescription: 'Напоминания о заметках Smart Notes',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    final tzWhen = tz.TZDateTime.from(when, tz.local);

    // Сначала пробуем точный будильник; если прошивка не дала право
    // (SecurityException/PlatformException на части китайских ROM),
    // откатываемся на неточное планирование — уведомление всё равно
    // доставляется, лишь с возможной задержкой в пределах окна Doze.
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzWhen,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } on PlatformException {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzWhen,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

/// Заглушка для тестов: ничего не планирует.
class NoopNotificationService implements NotificationService {
  final List<int> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<void> init() async {}
  @override
  Future<void> schedule(
      {required int id,
      required String title,
      required String body,
      required DateTime when}) async {
    scheduled.add(id);
  }
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
  @override
  Future<void> cancelAll() async {}
}
