import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/date_parser.dart';
import '../../../../core/utils/highlighted_text.dart';
import '../../models/note_attachment.dart';
import '../../state/notes_notifier.dart';
import '../../utils/attachment_picker.dart';

/// Центральная строка ввода (раздел 2.1 ТЗ).
/// Парсер в реальном времени подсвечивает даты золотистым.
class NoteInputBar extends ConsumerStatefulWidget {
  /// На экране Family все новые заметки автоматически семейные.
  final bool forceFamily;

  /// Показывать тумблер "Семейная".
  final bool showFamilyToggle;

  const NoteInputBar({
    super.key,
    this.forceFamily = false,
    this.showFamilyToggle = true,
  });

  @override
  ConsumerState<NoteInputBar> createState() => _NoteInputBarState();
}

class _NoteInputBarState extends ConsumerState<NoteInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final List<NoteAttachment> _attachments = [];
  DateParseResult _parsed = DateParseResult.empty;
  DateTime? _manualReminder;
  late bool _isFamily = widget.forceFamily;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _parsed = NaturalDateParser().parse(value));
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала введите текст заметки')),
      );
      return;
    }
    await ref.read(notesNotifierProvider.notifier).addFromText(
          text,
          isFamily: _isFamily,
          reminderOverride: _manualReminder,
          attachments: List.of(_attachments),
        );

    // Звук "тинь" + тактильный отклик (кастомный ассет подключим в v1.1).
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.mediumImpact();
    if (!mounted) return;

    _controller.clear();
    setState(() {
      _attachments.clear();
      _manualReminder = null;
      _parsed = DateParseResult.empty;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Заметка сохранена'), duration: Duration(seconds: 1)),
    );
    _focusNode.requestFocus();
  }

  Future<void> _pickManualReminder() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _manualReminder ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_manualReminder ?? DateTime.now()),
    );
    if (time == null) return;
    setState(() {
      _manualReminder =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _showAttachSheet() async {
    final choice = await showModalBottomSheet<_AttachChoice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Камера'),
              onTap: () => Navigator.pop(ctx, _AttachChoice.camera),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Галерея'),
              onTap: () => Navigator.pop(ctx, _AttachChoice.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF-документ'),
              onTap: () => Navigator.pop(ctx, _AttachChoice.pdf),
            ),
            ListTile(
              leading: const Icon(Icons.audiotrack_outlined),
              title: const Text('Аудио'),
              onTap: () => Navigator.pop(ctx, _AttachChoice.audio),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    final attachment = await switch (choice) {
      _AttachChoice.camera => AttachmentPicker.pickImage(camera: true),
      _AttachChoice.gallery => AttachmentPicker.pickImage(camera: false),
      _AttachChoice.pdf => AttachmentPicker.pickPdf(),
      _AttachChoice.audio => AttachmentPicker.pickAudio(),
    };
    if (attachment != null) setState(() => _attachments.add(attachment));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reminder = _manualReminder ?? _parsed.reminderDate;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          boxShadow: const [
            BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 4,
                  onChanged: _onChanged,
                  style: theme.textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    hintText: 'О чем напомнить?',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
                if (_controller.text.isNotEmpty && _parsed.spans.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Text.rich(
                      buildHighlightedSpan(
                        _controller.text,
                        _parsed.spans,
                        baseStyle: theme.textTheme.bodySmall!,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (reminder != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.alarm, size: 15, color: AppColors.gold),
                        const SizedBox(width: 4),
                        Text(
                          'Напомню: ${DateFormatter.reminder(reminder)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.gold),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => setState(() => _manualReminder = null),
                          child: const Icon(Icons.close, size: 14),
                        ),
                      ],
                    ),
                  ),
                if (_attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final a in _attachments)
                          Chip(
                            label: Text(a.name, overflow: TextOverflow.ellipsis),
                            visualDensity: VisualDensity.compact,
                            onDeleted: () =>
                                setState(() => _attachments.remove(a)),
                          ),
                      ],
                    ),
                  ),
                const Divider(height: 16),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Голосовой ввод (v1.1)',
                      icon: const Icon(Icons.mic_none),
                      color: theme.colorScheme.onSurface,
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Голосовой ввод появится в версии 1.1'),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Прикрепить файл',
                      icon: const Icon(Icons.attach_file),
                      color: theme.colorScheme.onSurface,
                      onPressed: _showAttachSheet,
                    ),
                    IconButton(
                      tooltip: 'Опции',
                      icon: const Icon(Icons.add_circle_outline),
                      color: theme.colorScheme.onSurface,
                      onPressed: _pickManualReminder,
                    ),
                    if (widget.showFamilyToggle) ...[
                      const Spacer(),
                      Text('Семейная', style: theme.textTheme.bodySmall),
                      Switch(
                        value: _isFamily,
                        onChanged: widget.forceFamily
                            ? null
                            : (v) => setState(() => _isFamily = v),
                      ),
                    ] else
                      const Spacer(),
                    IconButton(
                      tooltip: 'Сохранить',
                      icon: const Icon(Icons.send, color: AppColors.gold),
                      onPressed: _save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _AttachChoice { camera, gallery, pdf, audio }
