// Фрагмент для lib/main.dart после подключения Firebase.
// Заменяет блок выбора реализаций хранилища и сервисов.

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/services/firebase_messaging_service.dart';
import 'core/services/firebase_sync_service.dart';
import 'core/services/json_store.dart';
import 'core/services/notification_service.dart';

Future<void> bootstrapWithFirebase() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final docsDir = await getApplicationDocumentsDirectory();
  final store = JsonStore(docsDir); // остаётся локальным кэшем

  // Локальные таймеры + серверные push работают параллельно.
  final localNotifications = LocalNotificationService();
  await localNotifications.init();
  final fcm = FirebaseMessagingService();
  await fcm.init();

  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      notificationServiceProvider.overrideWithValue(localNotifications),
      syncServiceProvider.overrideWithValue(FirebaseSyncService()),
    ],
  );
  runApp(UncontrolledProviderScope(container: container, child: const SmartNotesApp()));
}
