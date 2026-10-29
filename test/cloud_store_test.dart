import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:smart_notes/features/cloud/data/cloud_store.dart';

void main() {
  late Directory directory;
  late CloudStore first;
  late CloudStore second;
  setUpAll(() {
    ffi.sqfliteFfiInit();
    databaseFactory = ffi.databaseFactoryFfi;
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cloud-store-');
    await setDatabasesPath(directory.path);
    first = await CloudStore.open('account');
    second = CloudStore(first.database, 'account');
  });
  tearDown(() async {
    await first.database.close();
    await directory.delete(recursive: true);
  });

  test('writes require a lease, not just a UI mutex', () async {
    await first.read();
    await expectLater(first.write({'notes': {}}), throwsStateError);
  });

  test('two engines cannot acquire the same lease simultaneously', () async {
    await first.withLease(() async {
      await expectLater(second.withLease(() async {}), throwsStateError);
      await first.read();
      await first.write({'notes': {'one': {}}});
    });
    await second.withLease(() async {
      expect((await second.read())['notes'], contains('one'));
    });
  });

  test('expired worker cannot overwrite the replacement worker', () async {
    await first.withLease(() async {
      await first.read();
      await first.database.update('cloud_leases', {'expires': 0});
      await second.withLease(() async {
        await second.read();
        await second.write({'notes': {'new-worker': {}}});
      });
      await expectLater(first.write({'notes': {'stale-worker': {}}}), throwsStateError);
    });
    expect((await second.read())['notes'], contains('new-worker'));
  });

  test('revision check rejects stale state even under a new lease', () async {
    await first.read();
    await second.withLease(() async {
      await second.read();
      await second.write({'notes': {'newer': {}}});
    });
    await first.withLease(() async {
      await expectLater(first.write({'notes': {'older': {}}}), throwsStateError);
    });
  });

  test('server/account namespaces do not share notes', () async {
    await first.withLease(() async {
      await first.read();
      await first.write({'notes': {'private': {}}});
    });
    final other = CloudStore(first.database, 'another-server-account');
    expect((await other.read())['notes'], isEmpty);
  });
}
