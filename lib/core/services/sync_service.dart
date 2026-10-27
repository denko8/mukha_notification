/// Статус облачной синхронизации для экрана настроек (раздел 2.4 ТЗ).
enum SyncStatus { idle, syncing, synced, offline, error }

/// Интерфейс облачной синхронизации.
///
/// В MVP реализована локальная заглушка [LocalSyncService], которая
/// помечает заметки как синхронизированные. Боевой `FirebaseSyncService`
/// (Realtime Database + Security Rules) реализуется по docs/BACKEND_SETUP.md
/// и подменяет провайдер без изменения UI.
abstract class SyncService {
  SyncStatus get status;
  DateTime? get lastSyncAt;
  Future<void> syncNow();
}

class LocalSyncService implements SyncService {
  @override
  SyncStatus status = SyncStatus.synced;
  @override
  DateTime? lastSyncAt = DateTime.now();

  @override
  Future<void> syncNow() async {
    status = SyncStatus.syncing;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    lastSyncAt = DateTime.now();
    status = SyncStatus.synced;
  }
}
