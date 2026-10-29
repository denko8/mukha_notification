import 'package:sqflite/sqflite.dart';

import '../../../core/services/notification_service.dart';

/// Persistent, account-scoped IDs. Never uses cancelAll (local notes coexist).
class CloudAlarms {
  final Database db;
  final NotificationService notifications;
  final String namespace;
  CloudAlarms(this.db, this.notifications, this.namespace);

  Future<void> cancel({bool otherAccounts = false}) async {
    final rows = await db.query('cloud_alarms',
      where: otherAccounts ? 'namespace != ?' : 'namespace = ?', whereArgs: [namespace]);
    for (final row in rows) {
      await notifications.cancel(-(row['notification_id'] as int));
    }
  }

  Future<void> reconcile(Map<String, dynamic> notes) async {
    await cancel(otherAccounts: true);
    await cancel();
    final desired = notes.entries.where((entry) {
      final item = entry.value as Map;
      final n = item['note'] as Map;
      final when = DateTime.tryParse(n['reminder_at'] as String? ?? '');
      return item['blocked'] == null && n['deleted'] != true && n['done'] != true &&
        when != null && when.isAfter(DateTime.now());
    }).toList();
    if (desired.isEmpty) return;
    final diagnostic = await notifications.diagnose();
    if (!diagnostic.notificationsAllowed || !diagnostic.exactAlarmsAllowed) {
      throw StateError('Заметки сохранены, но напоминания не поставлены: '
        'разрешите уведомления и точные будильники в настройках Android.');
    }
    for (final entry in desired) {
      await db.insert('cloud_alarms', {'namespace': namespace, 'note_id': entry.key},
        conflictAlgorithm: ConflictAlgorithm.ignore);
      final row = (await db.query('cloud_alarms', where: 'namespace = ? AND note_id = ?',
        whereArgs: [namespace, entry.key])).single;
      final n = (entry.value as Map)['note'] as Map;
      await notifications.schedule(id: -(row['notification_id'] as int),
        title: 'Напоминание · Облако', body: n['text'] as String,
        when: DateTime.parse(n['reminder_at'] as String));
    }
  }
}
