// Перенести в lib/core/services/firebase_messaging_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_service.dart';

/// Серверные push через FCM. Локальный LocalNotificationService остаётся
/// fallback'ом для офлайна и точных таймеров на устройстве.
class FirebaseMessagingService implements NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  Future<void> setup() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await _messaging.getToken();
    // Сохранить токен: users/{uid}/tokens/{token} (см. firestore.rules).
    // ignore: avoid_print
    print('FCM token: $token');

    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      _local.show(
        message.hashCode,
        n.title ?? 'Smart Notes',
        n.body ?? '',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'smart_notes_reminders',
            'Напоминания',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    });
  }

  @override
  Future<void> init() => setup();

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    // План отправки хранит Cloud Scheduler + Functions (functions_reminder.js),
    // клиент лишь пишет reminderAt в Firestore.
  }

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}
}
