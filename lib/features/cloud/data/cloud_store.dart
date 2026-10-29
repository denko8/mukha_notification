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
      version: 1, onCreate: (db, _) async {
        await db.execute('CREATE TABLE workspaces (namespace TEXT PRIMARY KEY, document TEXT NOT NULL)');
      });
    return CloudStore(db, namespace);
  }

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
