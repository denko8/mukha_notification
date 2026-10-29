import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_notes/features/cloud/data/cloud_api.dart';
import 'package:smart_notes/features/cloud/data/cloud_workspace.dart';

Map<String, dynamic> emptyState() => {'notes': <String, dynamic>{}};

void main() {
  test('Origin requires HTTPS, forbids URL credentials/path/query', () {
    expect(() => CloudApi.validateOrigin('http://example.com'), throwsFormatException);
    expect(() => CloudApi.validateOrigin('https://user:pass@example.com'), throwsFormatException);
    expect(() => CloudApi.validateOrigin('https://example.com/api'), throwsFormatException);
    expect(() => CloudApi.validateOrigin('https://example.com?token=x'), throwsFormatException);
    expect(CloudApi.validateOrigin('https://example.com/').host, 'example.com');
  });

  test('Draft is queued before network; failed persistence does not claim success', () async {
    var requests = 0;
    final api = CloudApi('https://example.com', client: MockClient((_) async {
      requests++;
      return http.Response('{}', 500);
    }));
    final workspace = CloudWorkspace(api, emptyState(), (_) async => throw StateError('disk full'));
    await expectLater(workspace.create('Текст'), throwsStateError);
    expect(workspace.notes, isEmpty);
    expect(requests, 0);
    api.close();
  });

  test('Network failure and workspace restart preserve operation ID and body', () async {
    Map<String, dynamic>? disk;
    final sent = <String>[];
    final api = CloudApi('https://example.com', client: MockClient((request) async {
      sent.add('${request.headers['idempotency-key']}|${request.body}');
      return http.Response('{}', 503);
    }));
    Future<void> persist(Map<String, dynamic> state) async {
      disk = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    }
    final workspace = CloudWorkspace(api, emptyState(), persist);
    await workspace.create('Офлайн');
    await expectLater(workspace.sync(), throwsA(isA<CloudApiException>()));
    final restored = CloudWorkspace(api, disk!, persist);
    await expectLater(restored.sync(), throwsA(isA<CloudApiException>()));
    expect(sent.length, 2);
    expect(sent[0], sent[1]);
    expect(restored.notes.values.single['operation'], isNotNull);
    api.close();
  });

  test('Pending draft cannot be edited into a different idempotent operation', () async {
    final api = CloudApi('https://example.com');
    final workspace = CloudWorkspace(api, emptyState(), (_) async {});
    await workspace.create('Первый текст');
    await expectLater(workspace.edit(workspace.notes.keys.single, 'Другой'), throwsStateError);
    expect(workspace.notes.values.single['note']['text'], 'Первый текст');
    api.close();
  });

  test('Version conflict preserves local text and server variant', () async {
    var body = <String, dynamic>{};
    final api = CloudApi('https://example.com', client: MockClient((request) async {
      if (request.method == 'PUT') {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 409);
      }
      if (request.url.path.startsWith('/notes/')) {
        return http.Response(jsonEncode({'id': request.url.pathSegments.last,
          'text': 'На сервере', 'version': 4, 'deleted': false, 'family_id': null}), 200);
      }
      // Stop before downloading: conflict must already be persisted.
      return http.Response('{}', 503);
    }));
    final workspace = CloudWorkspace(api, emptyState(), (_) async {});
    await workspace.create('Мой текст');
    final id = workspace.notes.keys.single;
    final oldKey = workspace.notes[id]['operation']['id'];
    await expectLater(workspace.sync(), throwsA(isA<CloudApiException>()));
    expect(workspace.notes[id]['note']['text'], 'Мой текст');
    expect(workspace.notes[id]['conflict']['text'], 'На сервере');
    await workspace.resolve(id, keepLocal: true);
    expect(workspace.notes[id]['operation']['body']['expected_version'], 4);
    expect(workspace.notes[id]['operation']['id'], isNot(oldKey));
    expect(body['expected_version'], 0);
    api.close();
  });

  test('Malformed change page never replaces the existing cache', () async {
    final original = {'notes': <String, dynamic>{'local': {'note': {
      'id': 'local', 'version': 1, 'text': 'Сохранено', 'family_id': null,
    }}}};
    final api = CloudApi('https://example.com', client: MockClient((request) async {
      if (request.method == 'POST') return http.Response(jsonEncode({
        'snapshot_id': 's', 'total': 2, 'family_ids': [],
      }), 201);
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response(jsonEncode({'snapshot_id': 's', 'total': 2,
        'notes': [], 'next_offset': null}), 200);
    }));
    final workspace = CloudWorkspace(api, original, (_) async {});
    await expectLater(workspace.sync(), throwsStateError);
    expect(workspace.notes['local']['note']['text'], 'Сохранено');
    api.close();
  });

  test('Failed change download does not delete cached data', () async {
    final api = CloudApi('https://example.com', client: MockClient((request) async {
      if (request.method == 'POST') return http.Response(jsonEncode({
        'snapshot_id': 's', 'total': 0, 'family_ids': [],
      }), 201);
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response('{}', 410);
    }));
    final workspace = CloudWorkspace(api, {'notes': <String, dynamic>{
      'cached': {'note': {'id': 'cached', 'text': 'Не потерять', 'version': 1, 'family_id': null}},
    }}, (_) async {});
    await expectLater(workspace.sync(), throwsA(isA<CloudApiException>()));
    expect(workspace.notes, contains('cached'));
    api.close();
  });
  test('Concurrent callers cannot overwrite each other in the local queue', () async {
    final api = CloudApi('https://example.com');
    final workspace = CloudWorkspace(api, emptyState(), (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });
    await Future.wait([workspace.create('Один'), workspace.create('Два')]);
    expect(workspace.notes.length, 2);
    api.close();
  });

  test('Lost local acknowledgement keeps original operation for replay', () async {
    var failWrites = false;
    final api = CloudApi('https://example.com', client: MockClient((request) async {
      return http.Response(jsonEncode({'id': request.url.pathSegments.last,
        'text': 'Текст', 'version': 1, 'deleted': false, 'family_id': null}), 200);
    }));
    final workspace = CloudWorkspace(api, emptyState(), (_) async {
      if (failWrites) throw StateError('disk full');
    });
    await workspace.create('Текст');
    final id = workspace.notes.keys.single;
    final key = workspace.notes[id]['operation']['id'];
    failWrites = true;
    await expectLater(workspace.sync(), throwsStateError);
    expect(workspace.notes[id]['operation']['id'], key);
    api.close();
  });

  test('Family scope and reminder survive queued create and edit', () async {
    final api = CloudApi('https://example.com');
    final workspace = CloudWorkspace(api, emptyState(), (_) async {});
    final when = DateTime.utc(2030, 1, 1, 14);
    await workspace.create('Общее дело', familyId: 'family-1', reminder: when);
    final id = workspace.notes.keys.single;
    expect(workspace.notes[id]['operation']['body']['family_id'], 'family-1');
    expect(workspace.notes[id]['operation']['body']['reminder_at'], when.toIso8601String());
    final serverNote = Map<String, dynamic>.from(workspace.notes[id]['note'] as Map);
    serverNote['version'] = 2;
    final confirmed = CloudWorkspace(api, {'notes': <String, dynamic>{
      id: {'note': serverNote},
    }}, (_) async {});
    await confirmed.edit(id, 'Правка участника');
    expect(confirmed.notes[id]['operation']['body']['family_id'], 'family-1');
    expect(confirmed.notes[id]['operation']['body']['reminder_at'], when.toIso8601String());
    api.close();
  });

  test('Reminder removal is an explicit null mutation', () async {
    final api = CloudApi('https://example.com');
    final workspace = CloudWorkspace(api, {'notes': <String, dynamic>{
      'n': {'note': {'id': 'n', 'text': 'Текст', 'version': 3,
        'family_id': 'f', 'reminder_at': '2030-01-01T12:00:00Z'}},
    }}, (_) async {});
    await workspace.setReminder('n', null);
    final body = workspace.notes['n']['operation']['body'] as Map;
    expect(body.containsKey('reminder_at'), isTrue);
    expect(body['reminder_at'], isNull);
    expect(body['family_id'], 'f');
    api.close();
  });

  test('Revoked family write becomes a private blocked draft and sync continues', () async {
    final api = CloudApi('https://example.com', client: MockClient((request) async {
      if (request.method == 'PUT') return http.Response('{}', 404);
      if (request.method == 'POST') return http.Response(jsonEncode({
        'snapshot_id': 's', 'total': 0, 'family_ids': [],
      }), 201);
      if (request.method == 'DELETE') return http.Response('', 204);
      return http.Response(jsonEncode({'cursor': 'cursor-1', 'has_more': false, 'family_ids': [], 'notes': []}), 200);
    }));
    final workspace = CloudWorkspace(api, emptyState(), (_) async {});
    await workspace.create('Не потерять правку', familyId: 'f');
    final id = workspace.notes.keys.single;
    await workspace.sync();
    expect(workspace.notes[id]['note']['text'], 'Не потерять правку');
    expect(workspace.notes[id]['note']['family_id'], isNull);
    expect(workspace.notes[id]['operation'], isNull);
    expect(workspace.notes[id]['blocked'], isNotNull);
    api.close();
  });

  test('Delta cursor survives local mutation and is sent on the next pull', () async {
    final calls = <String>[];
    final api = CloudApi('https://example.com', client: MockClient((request) async {
      calls.add(request.url.path);
      expect(request.url.queryParameters['cursor'], 'old-cursor');
      return http.Response(jsonEncode({'cursor': 'new-cursor', 'has_more': false,
        'family_ids': [], 'notes': [{'id': 'n', 'version': 2, 'text': 'Новое', 'family_id': null}]}), 200);
    }));
    final workspace = CloudWorkspace(api, {'cursor': 'old-cursor', 'notes': <String, dynamic>{
      'n': {'note': {'id': 'n', 'version': 1, 'text': 'Старое', 'family_id': null}},
      'untouched': {'note': {'id': 'untouched', 'version': 1, 'text': 'Без изменений', 'family_id': null}},
    }}, (_) async {});
    await workspace.sync();
    expect(workspace.state['cursor'], 'new-cursor');
    expect(workspace.notes['n']['note']['text'], 'Новое');
    expect(workspace.notes, contains('untouched'));
    expect(calls, ['/sync/changes']);
    api.close();
  });

  test('Cursor reset bootstraps without leaking revoked family cache', () async {
    var requests = 0;
    final api = CloudApi('https://example.com', client: MockClient((request) async {
      requests++;
      if (requests == 1) return http.Response(jsonEncode({'detail': {'code': 'sync_reset'}}), 409);
      expect(request.url.queryParameters.containsKey('cursor'), isFalse);
      return http.Response(jsonEncode({'cursor': 'reset-cursor', 'has_more': false,
        'family_ids': [], 'notes': []}), 200);
    }));
    final workspace = CloudWorkspace(api, {'cursor': 'old', 'notes': <String, dynamic>{
      'family-note': {'note': {'id': 'family-note', 'version': 1, 'text': 'Отозвано', 'family_id': 'f'}},
    }}, (_) async {});
    await workspace.sync();
    expect(workspace.notes, isEmpty);
    expect(workspace.state['cursor'], 'reset-cursor');
    api.close();
  });

  test('Failed page commit never advances the durable cursor', () async {
    final api = CloudApi('https://example.com', client: MockClient((request) async =>
      http.Response(jsonEncode({'cursor': 'new', 'has_more': false, 'family_ids': [], 'notes': []}), 200)));
    final workspace = CloudWorkspace(api, {'cursor': 'old', 'notes': <String, dynamic>{}},
      (_) async => throw StateError('disk full'));
    await expectLater(workspace.sync(), throwsStateError);
    expect(workspace.state['cursor'], 'old');
    api.close();
  });

  test('Object download never forwards backend bearer token', () async {
    final api = CloudApi('https://api.example.com', token: 'secret', client: MockClient((request) async {
      expect(request.url.host, 'objects.example.com');
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(request.followRedirects, isFalse);
      return http.Response.bytes([1, 2, 3], 200);
    }));
    expect(await api.downloadObject('https://objects.example.com/key?signature=test'), [1, 2, 3]);
    api.close();
  });

}
