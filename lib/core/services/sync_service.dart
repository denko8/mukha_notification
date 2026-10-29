/// Статус облачной синхронизации для экрана настроек (раздел 2.4 ТЗ).
enum SyncStatus { idle, syncing, synced, offline, error }

/// Интерфейс облачной синхронизации.
///
/// Пока backend не подключён, [LocalSyncService] явно сообщает об этом. Боевой `FirebaseSyncService`
/// (Realtime Database + Security Rules) реализуется по docs/BACKEND_SETUP.md
/// и подменяет провайдер без изменения UI.
abstract class SyncService {
  SyncStatus get status;
  DateTime? get lastSyncAt;
  Future<void> syncNow();
}

/// Облачный backend ещё не подключён. Не имитирует отправку данных.
class LocalSyncService implements SyncService {
  @override
  SyncStatus get status => SyncStatus.offline;

  @override
  DateTime? get lastSyncAt => null;

  @override
  Future<void> syncNow() async {
    throw UnsupportedError(
      'Облачная синхронизация пока не подключена. Заметки хранятся на устройстве.',
    );
  }
}
