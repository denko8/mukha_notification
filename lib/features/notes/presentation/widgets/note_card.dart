import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/date_parser.dart';
import '../../../../core/utils/highlighted_text.dart';
import '../../models/note.dart';
import '../../models/note_attachment.dart';

/// Карточка заметки: скругление 12px, мягкая тень (раздел 5 ТЗ).
class NoteCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (onToggleDone != null)
                      GestureDetector(
                        onTap: onToggleDone,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2, right: 10),
                          child: Icon(
                            note.done
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: note.done
                                ? AppColors.success
                                : AppColors.gold,
                            size: 22,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text.rich(
                        buildHighlightedSpan(note.text, spans, baseStyle: baseStyle),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                    if (showAuthor)
                      _Chip(
                        icon: Icons.person_outline,
                        label: note.authorName,
                      ),
                    if (note.pendingSync)
                      const _Chip(icon: Icons.cloud_off, label: 'Офлайн'),
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
