import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/services/json_store.dart';
import 'core/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Русские форматы дат (intl).
  await initializeDateFormatting('ru');

  // На web нет ни файловой системы (path_provider), ни локальных
  // уведомлений — используем in-memory хранилище и no-op сервис.
  // Боевой таргет — Android/iOS с персистентным JSON-хранилищем.
  final JsonStoreBase store;
  final NotificationService notifications;
  if (kIsWeb) {
    store = InMemoryJsonStore();
    notifications = NoopNotificationService();
  } else {
    final docsDir = await getApplicationDocumentsDirectory();
    store = JsonStore(docsDir);
    notifications = LocalNotificationService();
    await notifications.init();
  }

  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      notificationServiceProvider.overrideWithValue(notifications),
    ],
  );

  // Восстанавливаем напоминания после перезапуска.
  container.listen(notesNotifierProvider, (_, next) {
    next.whenData((_) => container.read(notesNotifierProvider.notifier).rescheduleAll());
  }, fireImmediately: true);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SmartNotesApp(),
    ),
  );
}
