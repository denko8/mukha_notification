import 'dart:convert';
import 'dart:io';

/// Контракт хранилища ключ-список/ключ-объект.
/// Реализации: [JsonStore] (файлы, мобильные/десктоп) и
/// [InMemoryJsonStore] (web, где файловой системы нет).
abstract class JsonStoreBase {
  Future<List<Map<String, dynamic>>> readList(String fileName);
  Future<void> writeList(String fileName, List<Map<String, dynamic>> items);
  Future<Map<String, dynamic>?> readJson(String fileName);
  Future<void> writeJson(String fileName, Map<String, dynamic> data);
}

/// Простое надёжное локальное хранилище в JSON-файлах.
///
/// Специально без кодогенерации (Isar/Realm требуют build_runner):
/// интерфейс репозитория совместим с Isar — замена не затронет UI.
/// Каталог инъектируется, поэтому класс тестируется без плагинов.
class JsonStore implements JsonStoreBase {
  final Directory directory;

  JsonStore(this.directory);

  File _file(String name) => File('${directory.path}${Platform.pathSeparator}$name');

  @override
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

  @override
  Future<void> writeList(String fileName, List<Map<String, dynamic>> items) async {
    final file = _file(fileName);
    if (!await directory.exists()) await directory.create(recursive: true);
    await file.writeAsString(json.encode(items));
  }

  @override
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

  @override
  Future<void> writeJson(String fileName, Map<String, dynamic> data) async {
    final file = _file(fileName);
    if (!await directory.exists()) await directory.create(recursive: true);
    await file.writeAsString(json.encode(data));
  }
}

/// Web-реализация: данные живут в памяти вкладки.
/// Используется только для предпросмотра UI в Chrome — после перезагрузки
/// страницы состояние сбрасывается. Боевой таргет — Android/iOS с [JsonStore].
class InMemoryJsonStore implements JsonStoreBase {
  final Map<String, Object?> _data = {};

  @override
  Future<List<Map<String, dynamic>>> readList(String fileName) async {
    final list = _data[fileName];
    if (list is! List) return [];
    return list.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> writeList(String fileName, List<Map<String, dynamic>> items) async {
    _data[fileName] = List<Map<String, dynamic>>.from(items);
  }

  @override
  Future<Map<String, dynamic>?> readJson(String fileName) async {
    final value = _data[fileName];
    return value is Map<String, dynamic> ? value : null;
  }

  @override
  Future<void> writeJson(String fileName, Map<String, dynamic> data) async {
    _data[fileName] = Map<String, dynamic>.from(data);
  }
}
