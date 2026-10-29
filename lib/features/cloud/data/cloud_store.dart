import 'dart:convert';
import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// One transactional document per server/account. No tokens/passwords here.
class CloudStore {
  final Database database;
  final String namespace;
  CloudStore(this.database, this.namespace);
  int _revision = 0;
  String? _leaseOwner;

  static Future<CloudStore> open(String namespace) async {
    final db = await openDatabase(p.join(await getDatabasesPath(), 'cloud_v1.db'),
      version: 4, onCreate: (db, _) async {
        await db.execute('CREATE TABLE workspaces (namespace TEXT PRIMARY KEY, document TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 0)');
        await _alarms(db);
        await _leases(db);
        await _localFiles(db);
      }, onUpgrade: (db, old, next) async {
        if (old < 2) await _alarms(db);
        if (old < 3) {
          await db.execute('ALTER TABLE workspaces ADD COLUMN revision INTEGER NOT NULL DEFAULT 0');
          await _leases(db);
        }
        if (old < 4) await _localFiles(db);
      });
    return CloudStore(db, namespace);
  }

  static Future<void> _alarms(Database db) => db.execute(
    'CREATE TABLE cloud_alarms (notification_id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'namespace TEXT NOT NULL, note_id TEXT NOT NULL, UNIQUE(namespace,note_id))');

  Future<Map<String, dynamic>> read() async {
    final rows = await database.query('workspaces', where: 'namespace = ?', whereArgs: [namespace]);
    _revision = rows.isEmpty ? 0 : rows.single['revision'] as int;
    return rows.isEmpty ? <String, dynamic>{'notes': <String, dynamic>{}}
        : jsonDecode(rows.single['document'] as String) as Map<String, dynamic>;
  }

  static Future<void> _leases(Database db) async {
    await db.execute('CREATE TABLE cloud_leases (id INTEGER PRIMARY KEY, owner TEXT NOT NULL, expires INTEGER NOT NULL)');
    await db.execute('CREATE TABLE cloud_uploads (id TEXT PRIMARY KEY, namespace TEXT NOT NULL, '
      'note_id TEXT NOT NULL, path TEXT NOT NULL, name TEXT NOT NULL, size INTEGER NOT NULL)');
    await db.execute('CREATE TABLE cloud_background_status (namespace TEXT PRIMARY KEY, message TEXT NOT NULL)');
  }

  static Future<void> _localFiles(Database db) => db.execute(
    'CREATE TABLE cloud_local_files (id TEXT PRIMARY KEY, namespace TEXT NOT NULL, '
    'note_id TEXT NOT NULL, path TEXT NOT NULL, name TEXT NOT NULL, size INTEGER NOT NULL)');

  Future<T> guarded<T>(Future<T> Function(Transaction txn) action) =>
      database.transaction((txn) async {
        final lease = await txn.query('cloud_leases', where: 'id = 1');
        if (_leaseOwner == null || lease.isEmpty || lease.single['owner'] != _leaseOwner ||
            (lease.single['expires'] as int) <= DateTime.now().millisecondsSinceEpoch) {
          throw StateError('Обработка очереди передана другому процессу. Повторите действие.');
        }
        return action(txn);
      });

  Future<void> write(Map<String, dynamic> data) async {
    final expected = _revision;
    await guarded((txn) async {
      final rows = await txn.query('workspaces', where: 'namespace = ?', whereArgs: [namespace]);
      final actual = rows.isEmpty ? 0 : rows.single['revision'] as int;
      if (actual != expected) throw StateError('Кэш обновился в фоне. Повторите действие.');
      await txn.insert('workspaces', {'namespace': namespace, 'document': jsonEncode(data),
        'revision': expected + 1}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    _revision = expected + 1;
  }

  Future<T> withLease<T>(Future<T> Function() action) async {
    final owner = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.transaction((txn) async {
      final rows = await txn.query('cloud_leases', where: 'id = 1');
      if (rows.isNotEmpty && (rows.single['expires'] as int) > now) {
        throw StateError('Синхронизация уже выполняется. Повторите через несколько секунд.');
      }
      await txn.insert('cloud_leases', {'id': 1, 'owner': owner, 'expires': now + 120000},
        conflictAlgorithm: ConflictAlgorithm.replace);
    });
    _leaseOwner = owner;
    // Paused/killed isolates lose the lease. Every commit also checks ownership
    // and revision, so a stale worker cannot overwrite a newer local document.
    final heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        await database.update('cloud_leases', {'expires': DateTime.now().millisecondsSinceEpoch + 120000},
          where: 'id = 1 AND owner = ? AND expires > ?',
          whereArgs: [owner, DateTime.now().millisecondsSinceEpoch]);
      } catch (_) { /* guarded() rejects stale/expired writes. */ }
    });
    try { return await action(); } finally {
      heartbeat.cancel();
      _leaseOwner = null;
      await database.delete('cloud_leases', where: 'id = 1 AND owner = ?', whereArgs: [owner]);
    }
  }
}
