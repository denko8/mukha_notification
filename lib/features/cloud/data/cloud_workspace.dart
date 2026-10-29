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
    final merged = {...state, ...next};
    await persist(merged);
    state = merged;
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
    await _pullChanges();
  }

  Future<void> _pullChanges() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      var cursor = state['cursor'] as String?;
      final bootstrap = cursor == null;
      final staged = <String, dynamic>{};
      try {
        for (var pageNumber = 0; pageNumber < 100; pageNumber++) {
          final query = Uri(queryParameters: {
            if (cursor != null) 'cursor': cursor, 'limit': '100',
          }).query;
          final page = await api.request('GET', '/sync/changes?$query');
          if (page['cursor'] is! String || page['has_more'] is! bool ||
              page['notes'] is! List || page['family_ids'] is! List) {
            throw StateError('Некорректная страница изменений. Кэш не заменён.');
          }
          final scopes = (page['family_ids'] as List).cast<String>();
          if (bootstrap && pageNumber == 0) {
            final permitted = Map<String, dynamic>.from(notes);
            var changed = false;
            for (final id in permitted.keys.toList()) {
              final local = permitted[id] as Map;
              final family = local['note']['family_id'];
              if (family != null && !scopes.contains(family)) {
                changed = true;
                if (local['operation'] != null) {
                  permitted[id] = {'note': {...local['note'] as Map, 'family_id': null},
                    'blocked': 'Доступ к семье отозван. Сохранён личный черновик.'};
                } else { permitted.remove(id); }
              }
            }
            // Drop revoked scopes as soon as the server confirms permissions,
            // even if a later bootstrap page fails to download.
            if (changed) await _commit({'notes': permitted, 'cursor': null});
          }
          final next = page['cursor'] as String;
          if (page['has_more'] == true && next == cursor) throw StateError('Курсор не продвинулся.');
          for (final row in page['notes'] as List) {
            if (row['id'] is! String || row['version'] is! int) throw StateError('Некорректная версия заметки');
            final previous = staged[row['id']];
            if (previous == null || previous['note']['version'] <= row['version']) {
              staged[row['id'] as String] = {'note': row};
            }
          }
          final complete = page['has_more'] == false;
          if (!bootstrap || complete) {
            final merged = bootstrap ? <String, dynamic>{} : Map<String, dynamic>.from(notes);
            for (final id in merged.keys.toList()) {
              final entry = merged[id] as Map;
              final familyId = entry['note']['family_id'];
              if (familyId != null && !scopes.contains(familyId)) {
                if (entry['operation'] != null) {
                  merged[id] = {'note': {...entry['note'] as Map, 'family_id': null},
                    'blocked': 'Доступ к семье отозван. Сохранён личный черновик.'};
                } else { merged.remove(id); }
              }
            }
            for (final entry in staged.entries) {
              final local = notes[entry.key] as Map?;
              if (local != null && (local['operation'] != null || local['blocked'] != null ||
                  (local['note']['version'] as int) > (entry.value['note']['version'] as int))) {
                merged[entry.key] = local;
              } else { merged[entry.key] = entry.value; }
            }
            if (bootstrap) {
              for (final id in notes.keys) {
                final local = notes[id] as Map;
                if (local['operation'] != null || local['blocked'] != null) {
                  final family = local['note']['family_id'];
                  merged[id] = family != null && !scopes.contains(family)
                    ? {'note': {...local['note'] as Map, 'family_id': null},
                       'blocked': 'Доступ к семье отозван. Сохранён личный черновик.'} : local;
                }
              }
            }
            // Cursor and merged notes commit as ONE SQLite document transaction.
            await _commit({'notes': merged, 'cursor': next});
            staged.clear();
          }
          cursor = next;
          if (complete) return;
        }
        throw StateError('Много изменений. Повторите обмен, чтобы продолжить.');
      } on CloudApiException catch (error) {
        if (error.status != 409 || error.code != 'sync_reset') rethrow;
        await _commit({'cursor': null});
      }
    }
    throw StateError('Семейные права изменяются. Повторите синхронизацию.');
  }
}
