import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/custom_category.dart';
import '../../utils/category_catalog.dart';

/// Результат нижнего листа выбора категории: либо выбран ключ, либо
/// пользователь попросил создать новую категорию.
class CategoryPickerResult {
  final String? categoryKey;
  final bool createRequested;

  const CategoryPickerResult.pick(this.categoryKey) : createRequested = false;
  const CategoryPickerResult.create()
      : categoryKey = null,
        createRequested = true;
}

/// Нижний лист со всеми категориями (встроенные + свои) и пунктом
/// «Создать категорию».
Future<CategoryPickerResult?> showCategoryPickerSheet(
  BuildContext context, {
  required CategoryCatalog catalog,
  required String selectedKey,
}) {
  return showModalBottomSheet<CategoryPickerResult>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Категория', style: Theme.of(ctx).textTheme.titleLarge),
          ),
          for (final key in catalog.allKeys)
            ListTile(
              leading: Icon(catalog.iconOf(key), color: AppColors.gold),
              title: Text(catalog.labelOf(key)),
              trailing: key == selectedKey
                  ? const Icon(Icons.check, color: AppColors.gold)
                  : null,
              onTap: () =>
                  Navigator.pop(ctx, CategoryPickerResult.pick(key)),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: AppColors.gold),
            title: const Text('Создать категорию'),
            onTap: () =>
                Navigator.pop(ctx, const CategoryPickerResult.create()),
          ),
        ],
      ),
    ),
  );
}

/// Введённые пользователем данные категории.
class CustomCategoryInput {
  final String label;
  final List<String> keywords;

  const CustomCategoryInput(this.label, this.keywords);
}

/// Диалог создания/редактирования пользовательской категории.
/// Уникальность названия валидируется через [CategoryCatalog.isLabelTaken].
Future<CustomCategoryInput?> showCustomCategoryDialog(
  BuildContext context, {
  required CategoryCatalog catalog,
  CustomCategory? existing,
}) {
  final labelController = TextEditingController(text: existing?.label ?? '');
  final keywordsController =
      TextEditingController(text: existing?.keywords.join(', ') ?? '');
  final formKey = GlobalKey<FormState>();

  return showDialog<CustomCategoryInput>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Новая категория' : 'Изменить категорию'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: labelController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Название',
                hintText: 'Например: Рыбалка',
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Укажите название';
                if (catalog.isLabelTaken(t, excludeId: existing?.id)) {
                  return 'Категория с таким названием уже есть';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: keywordsController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Слова для автоопределения',
                hintText: 'через запятую: рыбалка, спиннинг, озёра',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'По этим словам заметка сама попадёт в категорию даже без '
              'интернета. А облачный ИИ дополнительно распознаёт её по названию.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            final keywords = keywordsController.text
                .split(RegExp(r'[,\n]'))
                .map((e) => e.trim().toLowerCase())
                .where((e) => e.isNotEmpty)
                .toList();
            Navigator.pop(
              ctx,
              CustomCategoryInput(labelController.text.trim(), keywords),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}
