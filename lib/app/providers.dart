import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/services/json_store.dart';
import '../core/services/notification_service.dart';
import '../core/services/sync_service.dart';
import '../features/family/data/family_repository.dart';
import '../features/family/state/family_notifier.dart';
import '../features/notes/data/notes_repository.dart';
import '../features/notes/models/note.dart';
import '../features/notes/state/notes_notifier.dart';
import '../features/settings/state/settings_notifier.dart';

/// Инфраструктурные провайдеры.
/// [jsonStoreProvider] и [notificationServiceProvider] переопределяются
/// в main() (боевой запуск) и в тестах (временный каталог / заглушка).
final jsonStoreProvider = Provider<JsonStore>(
  (ref) => throw UnimplementedError('JsonStore must be overridden in main()'),
);

final uuidProvider = Provider<Uuid>((ref) => const Uuid());

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => LocalNotificationService(),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => LocalSyncService(),
);

final notesRepositoryProvider = Provider<NotesRepository>(
  (ref) => NotesRepository(
    ref.watch(jsonStoreProvider),
    ref.watch(notificationServiceProvider),
  ),
);

final familyRepositoryProvider = Provider<FamilyRepository>(
  (ref) => FamilyRepository(ref.watch(jsonStoreProvider)),
);

/// Состояние приложения.
final notesNotifierProvider =
    AsyncNotifierProvider<NotesNotifier, List<AppNote>>(NotesNotifier.new);

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final familyNotifierProvider =
    AsyncNotifierProvider<FamilyNotifier, List<FamilyMemberState>>(
        FamilyNotifier.new);

/// UI-фильтры.
final homeDateFilterProvider = StateProvider<DateTime?>((ref) => null);
final familyAuthorFilterProvider = StateProvider<String?>((ref) => null);
final homeSearchQueryProvider = StateProvider<String>((ref) => '');
