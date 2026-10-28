import 'package:flutter/material.dart';

import '../models/custom_category.dart';
import '../models/note_category.dart';

/// Каталог всех доступных категорий: семь встроенных + пользовательские.
///
/// Неизменяемый снапшот настроек: виджеты собирают его из
/// `AppSettings.customCategories` и через него резолвят ключи заметок
/// в названия и иконки. Если категорию удалили, а заметки с её ключом
/// остались, [labelOf]/[iconOf] безопасно вернут «Общее».
class CategoryCatalog {
  final List<CustomCategory> customs;

  const CategoryCatalog(this.customs);

  static const empty = CategoryCatalog([]);

  /// Все ключи в порядке отображения: сначала встроенные, затем свои.
  List<String> get allKeys => [
        for (final c in NoteCategory.values) c.name,
        for (final c in customs) CategoryKeys.forCustom(c.id),
      ];

  bool contains(String key) =>
      CategoryKeys.builtInByKey(key) != null || customOf(key) != null;

  CustomCategory? customOf(String key) {
    if (!CategoryKeys.isCustom(key)) return null;
    final id = CategoryKeys.customIdOf(key);
    for (final c in customs) {
      if (c.id == id) return c;
    }
    return null;
  }

  String labelOf(String key) {
    final built = CategoryKeys.builtInByKey(key);
    if (built != null) return built.label;
    return customOf(key)?.label ?? NoteCategory.general.label;
  }

  IconData iconOf(String key) {
    final built = CategoryKeys.builtInByKey(key);
    if (built != null) return built.icon;
    if (customOf(key) != null) return Icons.bookmark_outline;
    return NoteCategory.general.icon;
  }

  /// Поиск ключа по точному названию (фолбэк, если LLM вернёт label
  /// вместо ключа). Сравнение регистронезависимое.
  String? keyByLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    for (final c in NoteCategory.values) {
      if (c.label.toLowerCase() == lower) return c.name;
    }
    for (final c in customs) {
      if (c.label.toLowerCase() == lower) return CategoryKeys.forCustom(c.id);
    }
    return null;
  }

  /// true, если название уже занято другой категорией (встроенной или
  /// пользовательской). [excludeId] исключает редактируемую категорию.
  bool isLabelTaken(String label, {String? excludeId}) {
    final lower = label.trim().toLowerCase();
    if (lower.isEmpty) return false;
    for (final c in NoteCategory.values) {
      if (c.label.toLowerCase() == lower) return true;
    }
    for (final c in customs) {
      if (c.id != excludeId && c.label.toLowerCase() == lower) return true;
    }
    return false;
  }
}
