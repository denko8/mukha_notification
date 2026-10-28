import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Категория заметки — определяется локальным классификатором (P3 ТЗ),
/// пользователь может переопределить вручную.
enum NoteCategory {
  general('Общее', Icons.label_outline),
  work('Работа', Icons.work_outline),
  shopping('Покупки', Icons.shopping_basket_outlined),
  finance('Финансы', Icons.account_balance_wallet_outlined),
  health('Здоровье', Icons.favorite_outline),
  family('Семья', Icons.groups_outlined),
  idea('Идеи', Icons.lightbulb_outline);

  final String label;
  final IconData icon;

  const NoteCategory(this.label, this.icon);

  /// Единый цвет категории, чтобы не плодить палитру вне Japandi-гайда.
  Color get tint => AppColors.gold;
}

/// Ключи категорий, под которыми они хранятся в заметках и настройках.
///
/// Встроенная категория — это имя enum'а (`work`, `shopping`, …),
/// пользовательская — `custom:<uuid>`. Строки вместо enum позволяют
/// добавлять категории без миграций и кодогенерации.
class CategoryKeys {
  const CategoryKeys._();

  static const String general = 'general';
  static const String customPrefix = 'custom:';

  static bool isCustom(String key) => key.startsWith(customPrefix);

  static String forCustom(String id) => '$customPrefix$id';

  static String customIdOf(String key) => key.substring(customPrefix.length);

  /// Встроенная категория по ключу либо null, если ключ пользовательский
  /// или неизвестный.
  static NoteCategory? builtInByKey(String key) {
    for (final c in NoteCategory.values) {
      if (c.name == key) return c;
    }
    return null;
  }
}
