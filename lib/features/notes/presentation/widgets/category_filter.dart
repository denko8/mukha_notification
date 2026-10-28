import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../settings/models/app_settings.dart';
import '../../utils/category_catalog.dart';

/// Горизонтальный фильтр по категориям (P3 ИИ-классификация).
/// Строится из каталога: семь встроенных + пользовательские категории.
class CategoryFilter extends ConsumerWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const CategoryFilter({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final catalog = CategoryCatalog(settings.customCategories);

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: 'Все',
            icon: Icons.inbox_outlined,
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final key in catalog.allKeys)
            _FilterChip(
              label: catalog.labelOf(key),
              icon: catalog.iconOf(key),
              selected: selected == key,
              onTap: () => onChanged(key),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.gold : Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : AppColors.gold),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : null,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
