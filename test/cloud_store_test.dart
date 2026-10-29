import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_notes/features/cloud/data/cloud_api.dart';
import 'package:smart_notes/features/cloud/data/cloud_files.dart';
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
  test('Device-only attachment never calls API or enters upload queue', () async {
    var requests = 0;
    final api = CloudApi('https://example.com', client: MockClient((request) async {
      requests++;
      return http.Response('{}', 500);
    }));
    final original = File('${directory.path}/original.pdf');
    await original.writeAsString('%PDF-1.7 test');
    final files = CloudFiles(first, api, rootOverride: directory);
    await first.withLease(() => files.enqueue('note', original, 'original.pdf'));
    await original.delete();
    expect(requests, 0);
    expect(await files.pending(), isEmpty);
    final local = (await files.localFiles()).single;
    expect(await File(local['path'] as String).exists(), isTrue);
    api.close();
  });

  test('Original downloads only on demand and subsequent opens use verified cache', () async {
    var requests = 0;
    final bytes = utf8.encode('%PDF-1.7 cached');
    final api = CloudApi('https://example.com', token: 'bearer', client: MockClient((request) async {
      requests++;
      if (request.url.host == 'objects.example.com') {
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response.bytes(bytes, 200);
      }
      return http.Response(jsonEncode({'url': 'https://objects.example.com/private?signature=x'}), 200);
    }));
    final files = CloudFiles(first, api, rootOverride: directory);
    final meta = {'id': '11111111-1111-1111-1111-111111111111', 'mime': 'application/pdf',
      'size': bytes.length, 'sha256': sha256.convert(bytes).toString()};
    expect(requests, 0);
    final original = await files.download('note', meta);
    expect(await original.readAsBytes(), bytes);
    expect(requests, 2); // one authorization grant + direct object request
    await files.download('note', meta);
    expect(requests, 2); // no network when opening verified cache
    api.close();
  });

}
