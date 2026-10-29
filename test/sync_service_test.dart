import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notes/core/services/sync_service.dart';

void main() {
  test('Без backend нет ложного подтверждения синхронизации', () async {
    final service = LocalSyncService();
    expect(service.status, SyncStatus.offline);
    expect(service.lastSyncAt, isNull);
    await expectLater(service.syncNow(), throwsUnsupportedError);
    expect(service.status, SyncStatus.offline);
    expect(service.lastSyncAt, isNull);
  });
}
