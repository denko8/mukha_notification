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
  final Directory? rootOverride;
  CloudFiles(this.store, this.api, {this.rootOverride});

  Future<Directory> _directory() async {
    final base = rootOverride ?? await getApplicationDocumentsDirectory();
    final tag = sha256.convert(utf8.encode(store.namespace)).toString();
    return Directory(p.join(base.path, 'cloud_files', tag)).create(recursive: true);
  }

  Future<void> enqueue(String noteId, File file, String name, {bool cloudCopy = false}) async {
    final extension = p.extension(name).toLowerCase();
    if (!['.pdf', '.jpg', '.jpeg', '.png', '.webp'].contains(extension)) {
      throw StateError('Поддерживаются PDF, JPEG, PNG и WebP.');
    }
    if (cloudCopy) {
      final plan = await api.request('GET', '/cloud/usage');
      if (plan['cloud_upload_allowed'] != true) {
        throw StateError('Облачная копия требует активного облачного тарифа. Выберите «Только на устройстве».');
      }
      if (plan['object_storage_ready'] != true) throw StateError('Администратор ещё не подключил хранилище.');
    }
    final size = await file.length();
    if (size <= 0 || size > 5 * 1024 * 1024) throw StateError('Файл должен быть не больше 5 МиБ.');
    final rows = await store.database.query('cloud_uploads', where: 'namespace = ?', whereArgs: [store.namespace]);
    if (cloudCopy && rows.length >= 20) throw StateError('Сначала отправьте файлы из очереди (лимит 20).');
    final id = const Uuid().v4();
    final copy = await file.copy(p.join((await _directory()).path, cloudCopy ? 'upload-$id' : 'local-$id$extension'));
    if (await copy.length() > 5 * 1024 * 1024) {
      await copy.delete();
      throw StateError('Файл изменился при копировании и превышает лимит.');
    }
    try {
      await store.guarded((txn) => txn.insert(cloudCopy ? 'cloud_uploads' : 'cloud_local_files', {
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

  Future<List<Map<String, Object?>>> localFiles() => store.database.query('cloud_local_files',
    where: 'namespace = ?', whereArgs: [store.namespace]);

  Future<void> deleteLocal(String id) async {
    final rows = await store.database.query('cloud_local_files',
      where: 'namespace = ? AND id = ?', whereArgs: [store.namespace, id]);
    if (rows.isEmpty) return;
    await store.guarded((txn) => txn.delete('cloud_local_files',
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
    final extension = switch (attachment['mime']) {
      'application/pdf' => '.pdf', 'image/png' => '.png',
      'image/jpeg' => '.jpg', 'image/webp' => '.webp', _ => throw StateError('Неизвестный тип файла'),
    };
    final directory = await _directory();
    final file = File(p.join(directory.path, '$id$extension'));
    if (await file.exists()) {
      final cached = await file.readAsBytes();
      if (cached.length == attachment['size'] && sha256.convert(cached).toString() == attachment['sha256']) {
        await file.setLastModified(DateTime.now());
        return file;
      }
    }
    final grant = await api.request('GET', '/notes/$noteId/attachments/$id/download-url');
    final bytes = grant['url'] == null
      ? await api.binary('GET', '/notes/$noteId/attachments/$id')
      : await api.downloadObject(grant['url'] as String);
    if (bytes.length != attachment['size'] || sha256.convert(bytes).toString() != attachment['sha256']) {
      throw StateError('Контрольная сумма вложения не совпала. Файл не открыт.');
    }
    await file.writeAsBytes(bytes, flush: true);
    await _trimCache(directory, keep: file.path);
    return file;
  }
  Future<void> _trimCache(Directory directory, {required String keep}) async {
    final caches = <File>[];
    var total = 0;
    await for (final entry in directory.list()) {
      if (entry is File && RegExp(r'^[0-9a-fA-F-]{36}\.(pdf|png|jpg|webp)$').hasMatch(p.basename(entry.path))) {
        caches.add(entry);
        total += await entry.length();
      }
    }
    final times = <String, DateTime>{};
    for (final file in caches) { times[file.path] = await file.lastModified(); }
    caches.sort((a, b) => times[a.path]!.compareTo(times[b.path]!));
    for (final file in caches) {
      if (total <= 100 * 1024 * 1024) break;
      if (file.path != keep) {
        total -= await file.length();
        await file.delete();
      }
    }
    // local-* files and upload-* originals are NEVER evicted as cache.
  }

}
