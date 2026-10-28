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
