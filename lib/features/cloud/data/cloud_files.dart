import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'cloud_api.dart';
import 'cloud_store.dart';
import 'cloud_workspace.dart';

/// Queue references an immutable private copy, never a gallery/file-provider path.
class CloudFiles {
  final CloudStore store;
  final CloudApi api;
  CloudFiles(this.store, this.api);

  Future<Directory> _directory() async {
    final base = await getApplicationDocumentsDirectory();
    final tag = sha256.convert(utf8.encode(store.namespace)).toString();
    return Directory(p.join(base.path, 'cloud_files', tag)).create(recursive: true);
  }

  Future<void> enqueue(String noteId, File file, String name) async {
    final size = await file.length();
    if (size <= 0 || size > 5 * 1024 * 1024) throw StateError('Файл должен быть не больше 5 МиБ.');
    final rows = await store.database.query('cloud_uploads', where: 'namespace = ?', whereArgs: [store.namespace]);
    if (rows.length >= 20) throw StateError('Сначала отправьте файлы из очереди (лимит 20).');
    final id = const Uuid().v4();
    final copy = await file.copy(p.join((await _directory()).path, 'upload-$id'));
    if (await copy.length() > 5 * 1024 * 1024) {
      await copy.delete();
      throw StateError('Файл изменился при копировании и превышает лимит.');
    }
    try {
      await store.guarded((txn) => txn.insert('cloud_uploads', {
        'id': id, 'namespace': store.namespace, 'note_id': noteId, 'path': copy.path,
        'name': p.basename(name), 'size': size,
      }));
    } catch (_) { await copy.delete(); rethrow; }
  }

  Future<List<Map<String, Object?>>> pending() => store.database.query('cloud_uploads',
    where: 'namespace = ?', whereArgs: [store.namespace]);

  Future<void> discard(String id) async {
    final rows = await store.database.query('cloud_uploads',
      where: 'namespace = ? AND id = ?', whereArgs: [store.namespace, id]);
    if (rows.isEmpty) return;
    await store.guarded((txn) => txn.delete('cloud_uploads',
      where: 'namespace = ? AND id = ?', whereArgs: [store.namespace, id]));
    final file = File(rows.single['path'] as String);
    if (await file.exists()) await file.delete();
  }

  Future<void> uploadPending(CloudWorkspace workspace) async {
    for (final item in await pending()) {
      final noteId = item['note_id'] as String;
      final note = workspace.notes[noteId] as Map?;
      if (note == null || note['blocked'] != null || note['conflict'] != null ||
          note['operation'] != null || (note['note'] as Map)['deleted'] == true) continue;
      final file = File(item['path'] as String);
      if (!await file.exists()) throw StateError('Копия вложения отсутствует. Удалите его из очереди и выберите заново.');
      await api.binary('PUT', '/notes/$noteId/attachments/${item['id']}',
        bytes: await file.readAsBytes(), name: item['name'] as String);
      await discard(item['id'] as String);
    }
  }

  Future<File> download(String noteId, Map attachment) async {
    final id = attachment['id'] as String;
    // UUID is validated before being used in a local filesystem path.
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) throw StateError('Некорректный ID вложения');
    final bytes = await api.binary('GET', '/notes/$noteId/attachments/$id');
    if (bytes.length != attachment['size'] || sha256.convert(bytes).toString() != attachment['sha256']) {
      throw StateError('Контрольная сумма вложения не совпала. Файл не открыт.');
    }
    final extension = switch (attachment['mime']) {
      'application/pdf' => '.pdf', 'image/png' => '.png',
      'image/jpeg' => '.jpg', 'image/webp' => '.webp', _ => throw StateError('Неизвестный тип файла'),
    };
    final file = File(p.join((await _directory()).path, '$id$extension'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
