import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../notes/models/custom_category.dart';
import '../../models/app_settings.dart';
import '../../../notes/models/note_category.dart';
import '../../../notes/presentation/widgets/category_picker_sheet.dart';
import '../../../notes/utils/category_catalog.dart';

/// Управление категориями: встроенные доступны только на чтение,
/// пользовательские можно создавать, редактировать и удалять.
class CategoryManageScreen extends ConsumerWidget {
  const CategoryManageScreen({super.key});

  Future<void> _create(
      BuildContext context, WidgetRef ref, CategoryCatalog catalog) async {
    final input =
        await showCustomCategoryDialog(context, catalog: catalog);
    if (input == null) return;
    await ref.read(settingsProvider.notifier).addCustomCategory(
          label: input.label,
          keywords: input.keywords,
        );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref,
      CategoryCatalog catalog, CustomCategory existing) async {
    final input = await showCustomCategoryDialog(
      context,
      catalog: catalog,
      existing: existing,
    );
    if (input == null) return;
    await ref.read(settingsProvider.notifier).updateCustomCategory(
          existing.copyWith(label: input.label, keywords: input.keywords),
        );
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, CustomCategory custom) async {
    final notesCount = (ref.read(notesNotifierProvider).valueOrNull ?? [])
        .where((n) => n.categoryKey == CategoryKeys.forCustom(custom.id))
        .length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Удалить «${custom.label}»?'),
        content: Text(notesCount > 0
            ? 'Категория удалится, а $notesCount заметок из неё переедут '
                'в «Общее». Действие нельзя отменить.'
            : 'Категория удалится. Действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final key = CategoryKeys.forCustom(custom.id);
    await ref.read(settingsProvider.notifier).removeCustomCategory(custom.id);
    await ref
        .read(notesNotifierProvider.notifier)
        .remapCategory(key, CategoryKeys.general);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final catalog = CategoryCatalog(settings.customCategories);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Мои категории')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.gold,
        onPressed: () => _create(context, ref, catalog),
        icon: const Icon(Icons.add),
        label: const Text('Категория'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.goldSoft,
              borderRadius: BorderRadius.circular(AppColors.radiusCard),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Icon(Icons.auto_awesome,
                    size: 18, color: AppColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Свои категории приложение распознаёт по ключевым словам '
                    'даже без интернета, а облачный ИИ — ещё и по названию.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Встроенные', style: theme.textTheme.titleLarge),
          for (final c in NoteCategory.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(c.icon, color: AppColors.gold),
              title: Text(c.label),
              subtitle: const Text('Встроенная, изменить нельзя'),
            ),
          const SizedBox(height: 16),
          Text('Свои категории', style: theme.textTheme.titleLarge),
          if (settings.customCategories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Пока пусто. Нажмите «Категория» внизу, чтобы создать свою.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          for (final custom in settings.customCategories)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:  Icon(Icons.bookmark_outline,
                  color: AppColors.gold),
              title: Text(custom.label),
              subtitle: Text(
                custom.keywords.isEmpty
                    ? 'Без ключевых слов — распознаёт только ИИ'
                    : 'Слова: ${custom.keywords.join(', ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Изменить',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(context, ref, catalog, custom),
                  ),
                  IconButton(
                    tooltip: 'Удалить',
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.danger),
                    onPressed: () => _delete(context, ref, custom),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 88),
        ],
      ),
    );
  }
}
