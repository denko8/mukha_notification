import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/services/notification_service.dart';
import 'cloud_alarms.dart';
import 'cloud_api.dart';
import 'cloud_session.dart';
import 'cloud_store.dart';
import 'cloud_workspace.dart';
import 'cloud_files.dart';

const _task = 'smartnotes.cloud.periodic.v1';

@pragma('vm:entry-point')
void cloudBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    if (task != _task) return true;
    WidgetsFlutterBinding.ensureInitialized();
    if (!await CloudSession.backgroundEnabled()) return true;
    final session = await CloudSession.restore();
    if (session == null) return true;
    final store = await CloudStore.open(session.namespace);
    CloudApi? api;
    try {
      await store.withLease(() async {
        // Logout/account switch may have happened while this job was waiting.
        final current = await CloudSession.restore();
        if (!await CloudSession.backgroundEnabled() ||
            current?.namespace != session.namespace || current?.token != session.token) return;
        api = CloudApi(session.origin, token: session.token);
        final workspace = CloudWorkspace(api!, await store.read(), store.write);
        await workspace.sync();
        await CloudFiles(store, api!).uploadPending(workspace);
        await workspace.sync();
        final notifications = LocalNotificationService();
        // Never launch permission prompts from a background isolate.
        await notifications.initBackground();
        await CloudAlarms(store.database, notifications, session.namespace).reconcile(workspace.notes);
        await store.guarded((txn) => txn.insert('cloud_background_status', {
          'namespace': session.namespace,
          'message': jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), 'ok': true}),
        }, conflictAlgorithm: ConflictAlgorithm.replace));
      });
      return true;
    } catch (error) {
      // No tokens or note content in status. Queue remains durable for retry.
      await store.database.insert('cloud_background_status', {
        'namespace': session.namespace,
        'message': jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), 'ok': false,
          'reason': error is CloudApiException ? error.message : 'Фоновый обмен не завершён. Откройте облако и повторите.'}),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (error is CloudApiException && error.status == 401) {
        await CloudBackground.disable();
        return true;
      }
      return false;
    } finally { api?.close(); }
  });
}

// Exported here to keep the callback's platform dependencies in one place.
// sqflite constants are needed inside the background isolate too.
class CloudBackground {
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<void> initialize() async {
    if (supported) await Workmanager().initialize(cloudBackgroundDispatcher);
  }
  static Future<void> enable() async {
    if (!supported) return;
    await Workmanager().registerPeriodicTask(_task, _task,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1));
    await CloudSession.setBackgroundEnabled(true);
  }
  static Future<void> disable() async {
    await CloudSession.setBackgroundEnabled(false);
    if (supported) await Workmanager().cancelByUniqueName(_task);
  }
}
