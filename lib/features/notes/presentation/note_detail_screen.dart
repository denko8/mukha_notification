import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/date_parser.dart';
import '../../../core/utils/highlighted_text.dart';
import '../models/note.dart';
import '../models/note_attachment.dart';
import '../state/notes_notifier.dart';
import 'note_edit_screen.dart';

class NoteDetailScreen extends ConsumerWidget {
  final String noteId;

  const NoteDetailScreen({super.key, required this.noteId});

  AppNote? _find(List<AppNote> notes) {
    for (final n in notes) {
      if (n.id == noteId) return n;
    }
    return null;
  }

  Future<void> _editReminder(BuildContext context, WidgetRef ref, AppNote note) async {
    final date = await showDatePicker(
      context: context,
      initialDate: note.reminderAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(note.reminderAt ?? DateTime.now()),
    );
    if (time == null) return;
    final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await ref.read(notesNotifierProvider.notifier).setReminder(note, when);
  }

  Future<void> _exportPdf(AppNote note) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Smart Notes — заметка',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 12),
          pw.Text(note.text, style: const pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 24),
          if (note.reminderAt != null)
            pw.Text('Напоминание: ${DateFormatter.full(note.reminderAt!)}'),
          pw.Text('Создано: ${DateFormatter.full(note.createdAt)}'),
          pw.Text('Изменено: ${DateFormatter.full(note.updatedAt)}'),
          if (note.isFamily) pw.Text('Семейная заметка, автор: ${note.authorName}'),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, AppNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: const Text('Действие нельзя будет отменить.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(notesNotifierProvider.notifier).remove(note.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesNotifierProvider).valueOrNull ?? [];
    final note = _find(notes);
    if (note == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final parsed = NaturalDateParser().parse(note.text);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Заметка'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'edit':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => NoteEditScreen(noteId: note.id)),
                  );
                case 'delete':
                  await _confirmDelete(context, ref, note);
                case 'share':
                  await Share.share(
                    note.reminderAt != null
                        ? '${note.text}\nНапоминание: ${DateFormatter.full(note.reminderAt!)}'
                        : note.text,
                  );
                case 'pdf':
                  await _exportPdf(note);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Редактировать')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
              PopupMenuItem(value: 'share', child: Text('Поделиться')),
              PopupMenuItem(value: 'pdf', child: Text('Экспортировать в PDF')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Текст заметки с кликабельными датами.
          Text.rich(
            buildHighlightedSpan(
              note.text,
              parsed.spans,
              baseStyle: theme.textTheme.bodyLarge!,
              tappable: true,
              onDateTap: () => _editReminder(context, ref, note),
            ),
          ),
          const SizedBox(height: 20),

          // Блок напоминания.
          _ReminderBlock(note: note, onEdit: () => _editReminder(context, ref, note)),
          const SizedBox(height: 20),

          if (note.attachments.isNotEmpty) ...[
            Text('Вложения', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            ...note.attachments.map((a) => _AttachmentTile(attachment: a)),
            const SizedBox(height: 20),
          ],

          // История.
          Text(
            'Создано: ${DateFormatter.history(note.createdAt)}.\n'
            'Изменено: ${DateFormatter.history(note.updatedAt)}.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (note.isFamily)
            Text('Семейная заметка · автор: ${note.authorName}',
                style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ReminderBlock extends ConsumerWidget {
  final AppNote note;
  final VoidCallback onEdit;

  const _ReminderBlock({required this.note, required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: note.reminderAt != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.alarm, color: AppColors.gold),
                    const SizedBox(width: 8),
                    Text(DateFormatter.reminder(note.reminderAt!),
                        style: theme.textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.block),
                      label: const Text('Отключить'),
                      onPressed: () =>
                          ref.read(notesNotifierProvider.notifier).setReminder(note, null),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.edit),
                      label: const Text('Изменить'),
                      onPressed: onEdit,
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text('Хочешь добавить напоминание?',
                      style: theme.textTheme.bodyLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.add_alarm, color: AppColors.gold),
                  onPressed: onEdit,
                ),
              ],
            ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final NoteAttachment attachment;

  const _AttachmentTile({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (attachment.type) {
      case AttachmentType.image:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppColors.radiusCard),
            child: Image.file(
              File(attachment.path),
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ListTile(
                leading: Icon(Icons.broken_image_outlined),
                title: Text('Файл недоступен'),
              ),
            ),
          ),
        );
      case AttachmentType.pdf:
        return Card(
          child: ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.danger),
            title: Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text('PDF-документ'),
            trailing: TextButton(
              child: const Text('Открыть'),
              onPressed: () => Printing.openFile(attachment.path),
            ),
          ),
        );
      case AttachmentType.audio:
        return Card(
          child: ListTile(
            leading: const Icon(Icons.audiotrack_outlined, color: AppColors.gold),
            title: Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.play_circle_outline),
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Аудиоплеер появится в версии 1.1')),
              ),
            ),
          ),
        );
      case AttachmentType.other:
        return Card(
          child: ListTile(
            leading: const Icon(Icons.attach_file),
            title: Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
    }
  }
}
