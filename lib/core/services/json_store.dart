import 'dart:convert';
import 'dart:io';

/// Простое надёжное локальное хранилище в JSON-файлах.
///
/// Специально без кодогенерации (Isar/Realm требуют build_runner):
/// интерфейс репозитория совместим с Isar — замена не затронет UI.
/// Каталог инъектируется, поэтому класс тестируется без плагинов.
class JsonStore {
  final Directory directory;

  JsonStore(this.directory);

  File _file(String name) => File('${directory.path}${Platform.pathSeparator}$name');

  Future<List<Map<String, dynamic>>> readList(String fileName) async {
    final file = _file(fileName);
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final list = json.decode(raw) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } on FormatException {
      return [];
    }
  }

  Future<void> writeList(String fileName, List<Map<String, dynamic>> items) async {
    final file = _file(fileName);
    if (!await directory.exists()) await directory.create(recursive: true);
    await file.writeAsString(json.encode(items));
  }

  Future<Map<String, dynamic>?> readJson(String fileName) async {
    final file = _file(fileName);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return json.decode(raw) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeJson(String fileName, Map<String, dynamic> data) async {
    final file = _file(fileName);
    if (!await directory.exists()) await directory.create(recursive: true);
    await file.writeAsString(json.encode(data));
  }
}
