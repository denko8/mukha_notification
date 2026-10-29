import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// One transactional document per server/account. No tokens/passwords here.
class CloudStore {
  final Database database;
  final String namespace;
  CloudStore(this.database, this.namespace);

  static Future<CloudStore> open(String namespace) async {
    final db = await openDatabase(p.join(await getDatabasesPath(), 'cloud_v1.db'),
      version: 2, onCreate: (db, _) async {
        await db.execute('CREATE TABLE workspaces (namespace TEXT PRIMARY KEY, document TEXT NOT NULL)');
        await _alarms(db);
      }, onUpgrade: (db, old, next) async {
        if (old < 2) await _alarms(db);
      });
    return CloudStore(db, namespace);
  }

  static Future<void> _alarms(Database db) => db.execute(
    'CREATE TABLE cloud_alarms (notification_id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'namespace TEXT NOT NULL, note_id TEXT NOT NULL, UNIQUE(namespace,note_id))');

  Future<Map<String, dynamic>> read() async {
    final rows = await database.query('workspaces', where: 'namespace = ?', whereArgs: [namespace]);
    return rows.isEmpty ? <String, dynamic>{'notes': <String, dynamic>{}}
        : jsonDecode(rows.single['document'] as String) as Map<String, dynamic>;
  }

  Future<void> write(Map<String, dynamic> data) async {
    await database.transaction((txn) async {
      await txn.insert('workspaces', {'namespace': namespace, 'document': jsonEncode(data)},
        conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
}
