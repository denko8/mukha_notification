import 'package:uuid/uuid.dart';

import 'cloud_api.dart';

/// Calls are serialized. A mutation body/key stays immutable until acknowledged.
/// Persistence is injectable for tests; the application uses transactional SQLite.
class CloudWorkspace {
  final CloudApi api;
  final Future<void> Function(Map<String, dynamic>) persist;
  Map<String, dynamic> state;
  CloudWorkspace(this.api, this.state, this.persist);
  Map<String, dynamic> get notes => state['notes'] as Map<String, dynamic>;

  Future<void> _commit(Map<String, dynamic> next) async {
    await persist(next);
    state = next;
  }

  Future<void> _tail = Future<void>.value();
  Future<void> _serial(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((Object _, StackTrace __) {});
    return next;
  }

  Future<void> create(String text, {String? familyId, DateTime? reminder}) =>
      _serial(() => _create(text, familyId: familyId, reminder: reminder));
  Future<void> edit(String id, String text, {bool delete = false}) =>
      _serial(() => _edit(id, text, delete: delete));
  Future<void> resolve(String id, {required bool keepLocal}) =>
      _serial(() => _resolve(id, keepLocal: keepLocal));
  Future<void> sync() => _serial(_sync);
  Future<void> setReminder(String id, DateTime? reminder) => _serial(() async {
    final entry = notes[id] as Map;
    if (entry['operation'] != null || entry['blocked'] != null) throw StateError('Сначала отправьте предыдущую правку.');
    final note = Map<String, dynamic>.from(entry['note'] as Map);
    final date = reminder?.toUtc().toIso8601String();
    await _commit({'notes': {...notes, id: {
      'note': {...note, 'reminder_at': date},
      'operation': {'id': const Uuid().v4(), 'method': 'PUT', 'body': {
        'expected_version': note['version'], 'text': note['text'],
        'family_id': note['family_id'], 'done': note['done'] ?? false,
        'category': note['category'] ?? 'general', 'reminder_at': date,
      }},
    }}});
  });

  void _validateText(String text) {
    if (text.trim().isEmpty || text.length > 20000) {
      throw ArgumentError('Текст должен содержать от 1 до 20000 символов.');
    }
  }

  Future<void> _create(String text, {String? familyId, DateTime? reminder}) async {
    _validateText(text);
    final id = const Uuid().v4();
    await _commit({'notes': {...notes, id: {
      'note': {'id': id, 'text': text.trim(), 'version': 0, 'family_id': familyId, 'reminder_at': reminder?.toUtc().toIso8601String(), 'deleted': false},
      'operation': {'id': const Uuid().v4(), 'method': 'PUT',
        'body': {'expected_version': 0, 'text': text.trim(), 'family_id': familyId,
          'reminder_at': reminder?.toUtc().toIso8601String()}},
    }}});
  }

  Future<void> _edit(String id, String text, {bool delete = false}) async {
    if (!delete) _validateText(text);
    final entry = Map<String, dynamic>.from(notes[id] as Map);
    final note = Map<String, dynamic>.from(entry['note'] as Map);
    if (entry['operation'] != null || entry['blocked'] != null) {
      throw StateError('Сначала синхронизируйте предыдущую правку заметки.');
    }
    final body = delete ? <String, dynamic>{'expected_version': note['version']}
        : <String, dynamic>{'expected_version': note['version'], 'text': text.trim(),
          'family_id': note['family_id'], 'done': note['done'] ?? false,
          'category': note['category'] ?? 'general', 'reminder_at': note['reminder_at']};
    await _commit({'notes': {...notes, id: {
      'note': {...note, 'text': text.trim(), 'deleted': delete},
      'operation': {'id': const Uuid().v4(), 'method': delete ? 'DELETE' : 'PUT', 'body': body},
    }}});
  }

  Future<void> _resolve(String id, {required bool keepLocal}) async {
    final entry = notes[id] as Map;
    final remote = entry['conflict'] as Map<String, dynamic>;
    if (!keepLocal) {
      await _commit({'notes': {...notes, id: {'note': remote}}});
      return;
    }
    if (remote['deleted'] == true) {
      throw StateError('Заметка удалена на сервере. Скопируйте свой текст в новую заметку.');
    }
    final operation = Map<String, dynamic>.from(entry['operation'] as Map);
    final body = Map<String, dynamic>.from(operation['body'] as Map);
    body['expected_version'] = remote['version'];
    await _commit({'notes': {...notes, id: {
      'note': entry['note'],
      'operation': {...operation, 'id': const Uuid().v4(), 'body': body},
    }}});
  }

  Future<void> _sync() async {
    for (final id in notes.keys.toList()) {
      final entry = notes[id] as Map;
      final operation = entry['operation'] as Map?;
      if (operation == null || entry['conflict'] != null) continue;
      try {
        final result = await api.request(operation['method'] as String, '/notes/$id',
          operationId: operation['id'] as String,
          body: Map<String, dynamic>.from(operation['body'] as Map));
        // Only this operation is acknowledged, after successful local persistence.
        await _commit({'notes': {...notes, id: {'note': result}}});
      } on CloudApiException catch (e) {
        if (e.status == 404 && (entry['note'] as Map)['family_id'] != null) {
          final note = Map<String, dynamic>.from(entry['note'] as Map);
          await _commit({...state, 'notes': {...notes, id: {
            'note': {...note, 'family_id': null},
            'blocked': 'Семейный доступ отозван. Текст сохранён как черновик, не отправлен.',
          }}});
          continue;
        }
        if (e.status != 409) rethrow;
        final remote = await api.request('GET', '/notes/$id');
        await _commit({'notes': {...notes, id: {...entry, 'conflict': remote}}});
      }
    }
    final snapshot = await api.request('POST', '/sync/snapshots');
    final sid = snapshot['snapshot_id'] as String;
    try {
      var offset = 0;
      final staged = <String, dynamic>{};
      while (true) {
        final page = await api.request('GET', '/sync/snapshots/$sid?offset=$offset&limit=100');
        if (page['snapshot_id'] != sid || page['total'] != snapshot['total']) {
          throw StateError('Некорректный снимок сервера. Данные не применены.');
        }
        for (final row in page['notes'] as List) {
          if (staged.containsKey(row['id'])) throw StateError('Повтор записи в снимке');
          staged[row['id'] as String] = {'note': row};
        }
        final next = page['next_offset'] as int?;
        if (next == null) break;
        if (next <= offset) throw StateError('Некорректная страница снимка');
        offset = next;
      }
      if (staged.length != snapshot['total']) throw StateError('Снимок неполный');
      await api.request('GET', '/sync/snapshots/$sid?limit=1');
      final scopes = (snapshot['family_ids'] as List).cast<String>();
      for (final id in notes.keys) {
        final entry = notes[id] as Map;
        final note = entry['note'] as Map;
        final familyId = note['family_id'];
        if (familyId != null && !scopes.contains(familyId)) continue;
        if (entry['operation'] != null || entry['blocked'] != null ||
            (staged[id] != null && (note['version'] as int) >
              (staged[id]['note']['version'] as int))) {
          staged[id] = entry;
        }
      }
      await _commit({'notes': staged});
    } finally {
      // Release is best effort: expiry will clean up if the connection is lost.
      try { await api.request('DELETE', '/sync/snapshots/$sid'); } catch (_) {}
    }
  }
}
