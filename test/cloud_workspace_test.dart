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

  test('Incomplete snapshot never replaces the existing cache', () async {
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

  test('Expired snapshot does not delete queued or cached data', () async {
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

}
