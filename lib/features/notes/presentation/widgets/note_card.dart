import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/date_parser.dart';
import '../../../../core/utils/highlighted_text.dart';
import '../../../settings/models/app_settings.dart';
import '../../models/note.dart';
import '../../models/note_attachment.dart';
import '../../models/note_category.dart' show CategoryKeys;
import '../../utils/category_catalog.dart';

/// Карточка заметки: скругление 12px, мягкая тень (раздел 5 ТЗ).
class NoteCard extends ConsumerWidget {
  final AppNote note;
  final bool showAuthor;
  final VoidCallback? onTap;
  final VoidCallback? onToggleDone;

  const NoteCard({
    super.key,
    required this.note,
    this.showAuthor = false,
    this.onTap,
    this.onToggleDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    final catalog = CategoryCatalog(settings.customCategories);
    final spans = NaturalDateParser().parse(note.text).spans;
    final baseStyle = theme.textTheme.bodyLarge!.copyWith(
      decoration: note.done ? TextDecoration.lineThrough : null,
      color: note.done ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : null,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (onToggleDone != null)
                      IconButton(
                        tooltip: note.done ? 'Вернуть в дела' : 'Отметить выполненным',
                        onPressed: onToggleDone,
                        icon: Icon(
                          note.done ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: note.done ? AppColors.success : AppColors.gold,
                          size: 22,
                        ),
                      ),
                    Expanded(
                      child: Text.rich(
                        buildHighlightedSpan(note.text, spans, baseStyle: baseStyle),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Шеринг в один тап, не открывая заметку: системный
                    // лист с Telegram / MAX / VK / WhatsApp и т.д.
                    IconButton(
                      tooltip: 'Поделиться',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: const EdgeInsets.all(4),
                      iconSize: 19,
                      icon: const Icon(Icons.ios_share),
                      color: AppColors.gold,
                      onPressed: () async {
                        try {
                          await ref.read(shareServiceProvider).shareNote(note);
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text(
                              'Не удалось открыть «Поделиться». Попробуйте ещё раз.',
                            )),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (note.reminderAt != null)
                      _Chip(
                        icon: Icons.alarm,
                        label: DateFormatter.reminder(note.reminderAt!),
                      ),
                    if (note.attachments.isNotEmpty)
                      _Chip(
                        icon: _attachmentIcon(note.attachments.first.type),
                        label: _attachmentLabel(note.attachments),
                      ),
                    if (note.aiAssisted)
                      const _Chip(icon: Icons.auto_awesome, label: 'ИИ'),
                    if (note.categoryKey != CategoryKeys.general &&
                        catalog.contains(note.categoryKey))
                      _Chip(
                        icon: catalog.iconOf(note.categoryKey),
                        label: catalog.labelOf(note.categoryKey),
                      ),
                    if (showAuthor)
                      _Chip(
                        icon: Icons.person_outline,
                        label: note.authorName,
                      ),
                    if (note.pendingSync)
                      const _Chip(icon: Icons.cloud_off, label: 'На устройстве'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _attachmentIcon(AttachmentType type) {
    switch (type) {
      case AttachmentType.image:
        return Icons.image_outlined;
      case AttachmentType.pdf:
        return Icons.picture_as_pdf_outlined;
      case AttachmentType.audio:
        return Icons.audiotrack_outlined;
      case AttachmentType.other:
        return Icons.attach_file;
    }
  }

  static String _attachmentLabel(List<NoteAttachment> list) {
    if (list.length == 1) {
      switch (list.first.type) {
        case AttachmentType.image:
          return 'Фото';
        case AttachmentType.pdf:
          return 'PDF';
        case AttachmentType.audio:
          return 'Аудио';
        case AttachmentType.other:
          return 'Файл';
      }
    }
    return 'Файлов: ${list.length}';
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.gold),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.gold)),
        ],
      ),
    );
  }
}
