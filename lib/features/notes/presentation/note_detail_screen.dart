import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/providers.dart';
import '../../../core/services/calendar_service.dart';
import '../../../core/services/ocr_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/date_parser.dart';
import '../../../core/utils/highlighted_text.dart';
import '../../settings/models/app_settings.dart';
import '../models/note.dart';
import '../models/note_attachment.dart';
import '../models/note_category.dart' show CategoryKeys;
import '../utils/category_catalog.dart';
import 'note_edit_screen.dart';
import 'widgets/audio_attachment_player.dart';
import 'widgets/category_picker_sheet.dart';

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

  Future<void> _pickCategory(BuildContext context, WidgetRef ref, AppNote note) async {
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const AppSettings();
    final catalog = CategoryCatalog(settings.customCategories);
    final picked = await showCategoryPickerSheet(
      context,
      catalog: catalog,
      selectedKey: note.categoryKey,
    );
    if (picked == null || !context.mounted) return;

    if (picked.createRequested) {
      final input = await showCustomCategoryDialog(context, catalog: catalog);
      if (input == null || !context.mounted) return;
      final created = await ref
          .read(settingsProvider.notifier)
          .addCustomCategory(label: input.label, keywords: input.keywords);
      await ref
          .read(notesNotifierProvider.notifier)
          .setCategory(note, CategoryKeys.forCustom(created.id));
      return;
    }
    await ref
        .read(notesNotifierProvider.notifier)
        .setCategory(note, picked.categoryKey!);
  }

  Future<void> _exportPdf(WidgetRef ref, AppNote note) async {
    final catalog = CategoryCatalog(
      ref.read(settingsProvider).valueOrNull?.customCategories ?? const [],
    );
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('Smart Notes — заметка',
                style: const pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 12),
          pw.Text(note.text, style: const pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 24),
          pw.Text('Категория: ${catalog.labelOf(note.categoryKey)}'),
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
    final catalog =
        CategoryCatalog(ref.watch(settingsProvider).valueOrNull?.customCategories ??
            const []);

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
                case 'category':
                  await _pickCategory(context, ref, note);
                case 'calendar':
                  if (note.reminderAt != null) {
                    await CalendarService.addEvent(
                      title: note.text,
                      start: note.reminderAt!,
                      notes: note.text,
                    );
                  }
                case 'delete':
                  await _confirmDelete(context, ref, note);
                case 'share':
                  // Шеринг открывает системный лист — оттуда можно выбрать
                  // Telegram, WhatsApp, SMS и другие приложения.
                  await Share.share(
                    note.reminderAt != null
                        ? '${note.text}\nНапоминание: ${DateFormatter.full(note.reminderAt!)}'
                        : note.text,
                  );
                case 'pdf':
                  await _exportPdf(ref, note);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
              const PopupMenuItem(value: 'category', child: Text('Изменить категорию')),
              if (note.reminderAt != null)
                const PopupMenuItem(value: 'calendar', child: Text('Добавить в календарь')),
              const PopupMenuItem(value: 'share', child: Text('Поделиться (Telegram и др.)')),
              const PopupMenuItem(value: 'pdf', child: Text('Экспортировать в PDF')),
              const PopupMenuItem(value: 'delete', child: Text('Удалить')),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(catalog.iconOf(note.categoryKey),
                  size: 18, color: AppColors.gold),
              const SizedBox(width: 6),
              Text(catalog.labelOf(note.categoryKey),
                  style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 20),

          // Блок напоминания.
          _ReminderBlock(note: note, onEdit: () => _editReminder(context, ref, note)),
          const SizedBox(height: 20),

          if (note.attachments.isNotEmpty) ...[
            Text('Вложения', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final a in note.attachments)
              _AttachmentTile(attachment: a, note: note),
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

class _AttachmentTile extends ConsumerWidget {
  final NoteAttachment attachment;
  final AppNote note;

  const _AttachmentTile({required this.attachment, required this.note});

  Future<void> _runOcr(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Распознаю текст…'), duration: Duration(seconds: 1)),
    );
    try {
      final text = await ref.read(ocrServiceProvider).extractTextFromImage(attachment.path);
      if (text.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Текст на изображении не найден')));
        return;
      }
      final merged = '${note.text}\n\n[OCR]\n$text';
      await ref.read(notesNotifierProvider.notifier).updateNote(note.copyWith(text: merged));
      messenger.showSnackBar(const SnackBar(content: Text('Текст добавлен в заметку')));
    } on OcrUnsupportedException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Не удалось распознать текст')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (attachment.type) {
      case AttachmentType.image:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.document_scanner_outlined, size: 18),
                  label: const Text('Распознать текст (OCR)'),
                  onPressed: () => _runOcr(context, ref),
                ),
              ),
            ],
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
              onPressed: () => OpenFilex.open(attachment.path),
            ),
          ),
        );
      case AttachmentType.audio:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AudioAttachmentPlayer(path: attachment.path, name: attachment.name),
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
