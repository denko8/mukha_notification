import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Снимок состояния системных разрешений на уведомления —
/// для экрана самодиагностики в настройках.
class NotificationDiagnostics {
  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;
  final int pendingCount;

  const NotificationDiagnostics({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
    required this.pendingCount,
  });
}

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

  /// Диагностика разрешений и очереди ожидающих уведомлений.
  Future<NotificationDiagnostics> diagnose();

  /// Тестовое уведомление через [delay] секунд — проверка канала
  /// и настроек прошивки без создания заметки.
  Future<void> scheduleTest({Duration delay = const Duration(seconds: 10)});
}

/// Id тестового уведомления: заметки используют hashCode uuid,
/// берём заведомо редкое положительное значение.
const int _testNotificationId = 2147483000;

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
      debugPrint('[NOTIFY] таймзона: $name');
    } catch (e) {
      // Если системную зону определить не удалось — остаёмся на UTC.
      debugPrint('[NOTIFY] таймзону определить не удалось: $e');
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
    final notifications =
        await androidPlugin?.requestNotificationsPermission();
    debugPrint('[NOTIFY] разрешение на уведомления: $notifications');
    // Android 12+: право на точные будильники. На части прошивок
    // (vivo/OPPO/Xiaomi) выдаётся через системный экран настроек.
    final exact = await androidPlugin?.requestExactAlarmsPermission();
    debugPrint('[NOTIFY] разрешение на точные будильники: $exact');
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
    if (!when.isAfter(DateTime.now())) {
      debugPrint('[NOTIFY] пропуск id=$id: время $when уже прошло');
      return;
    }

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
    debugPrint(
      '[NOTIFY] план id=$id на $when (tz=${tz.local.name}), '
      'через ${when.difference(DateTime.now()).inSeconds}с',
    );

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
      debugPrint('[NOTIFY] id=$id запланирован точным будильником');
    } on PlatformException catch (e) {
      debugPrint('[NOTIFY] точный будильник отклонён (${e.code}), '
          'перехожу на inexact');
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
      debugPrint('[NOTIFY] id=$id запланирован неточным будильником');
    }
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<NotificationDiagnostics> diagnose() async {
    if (!_ready) await init();
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final notifications =
        (await androidPlugin?.areNotificationsEnabled()) ?? false;
    final exact =
        (await androidPlugin?.canScheduleExactNotifications()) ?? false;
    final pending = await _plugin.pendingNotificationRequests();
    final result = NotificationDiagnostics(
      notificationsAllowed: notifications,
      exactAlarmsAllowed: exact,
      pendingCount: pending.length,
    );
    debugPrint(
      '[NOTIFY] диагностика: уведомления=$notifications, '
      'точные=$exact, в очереди=${pending.length}',
    );
    return result;
  }

  @override
  Future<void> scheduleTest({
    Duration delay = const Duration(seconds: 10),
  }) async {
    await schedule(
      id: _testNotificationId,
      title: 'Проверка Smart Notes',
      body: 'Если вы видите это уведомление — напоминания работают.',
      when: DateTime.now().add(delay),
    );
  }
}

/// Заглушка для тестов и web: ничего не планирует.
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

  @override
  Future<NotificationDiagnostics> diagnose() async =>
      const NotificationDiagnostics(
        notificationsAllowed: true,
        exactAlarmsAllowed: true,
        pendingCount: 0,
      );

  @override
  Future<void> scheduleTest({
    Duration delay = const Duration(seconds: 10),
  }) async {
    scheduled.add(_testNotificationId);
  }
}
