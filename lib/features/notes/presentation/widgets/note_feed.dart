import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/note.dart';
import 'note_card.dart';

/// Лента заметок: новые карточки выезжают (300ms ease-in-out),
/// свайп влево открывает удаление (раздел 2.1 ТЗ).
class NoteFeed extends ConsumerWidget {
  final List<AppNote> notes;
  final bool showAuthor;
  final String? emptyText;
  final VoidCallback? onResetFilters;
  final void Function(AppNote note) onOpen;

  const NoteFeed({
    super.key,
    required this.notes,
    required this.onOpen,
    this.showAuthor = false,
    this.emptyText,
    this.onResetFilters,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (notes.isEmpty) {
      return _EmptyState(
        icon: Icons.note_alt_outlined,
        onResetFilters: onResetFilters,
        text: emptyText ?? (showAuthor
            ? 'Здесь будут семейные заметки.\nДобавьте первую в поле выше.'
            : 'Здесь будут ваши заметки.\nНапишите выше, например: «Забрать заказ завтра в 14:00».'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final note = notes[i];
        // Key на id -> анимация проигрывается только у новых карточек.
        return KeyedSubtree(
          key: ValueKey('slide_${note.id}'),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 24),
                child: child,
              ),
            ),
            child: Dismissible(
              key: ValueKey(note.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(AppColors.radiusCard),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outline, color: Colors.white),
                    SizedBox(height: 4),
                    Text('Удалить', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              confirmDismiss: (_) => _confirmDelete(context),
              onDismissed: (_) =>
                  ref.read(notesNotifierProvider.notifier).remove(note.id),
              child: NoteCard(
                note: note,
                showAuthor: showAuthor,
                onTap: () => onOpen(note),
                onToggleDone: () =>
                    ref.read(notesNotifierProvider.notifier).toggleDone(note),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: const Text('Действие нельзя будет отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Удалить', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onResetFilters;

  const _EmptyState({
    required this.icon,
    required this.text,
    this.onResetFilters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // SingleChildScrollView: при открытой клавиатуре область ленты
    // сжимается до нескольких десятков px — скролл вместо overflow.
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.gold.withValues(alpha: 0.6)),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.textTheme.bodySmall?.color),
              ),
            ),
            if (onResetFilters != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onResetFilters,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Сбросить поиск и фильтры'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
