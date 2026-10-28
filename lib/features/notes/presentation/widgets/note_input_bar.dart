import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/date_parser.dart';
import '../../../../core/utils/highlighted_text.dart';
import '../../../ai/llm/ai_client_factory.dart';
import '../../../settings/models/app_settings.dart';
import '../../models/note_attachment.dart';
import '../../models/note_category.dart';
import '../../utils/attachment_picker.dart';
import '../../utils/note_classifier.dart';
import '../../utils/note_templates.dart';

/// Центральная строка ввода (раздел 2.1 ТЗ).
/// Парсер в реальном времени подсвечивает даты золотистым,
/// классификатор показывает предлагаемую категорию.
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
  NoteCategory? _manualCategory;
  late bool _isFamily = widget.forceFamily;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerChanged() => setState(_recomputeHints);

  void _recomputeHints() {
    _parsed = NaturalDateParser().parse(_controller.text);
  }

  NoteCategory get _suggestedCategory =>
      _manualCategory ?? NoteClassifier.classify(_controller.text);

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
          categoryOverride: _suggestedCategory,
        );

    // Звук "тинь" + тактильный отклик (кастомный ассет подключим в v1.1).
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.mediumImpact();
    if (!mounted) return;

    _controller.clear();
    setState(() {
      _attachments.clear();
      _manualReminder = null;
      _manualCategory = null;
      _parsed = DateParseResult.empty;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Заметка сохранена'),
        duration: Duration(seconds: 1),
      ),
    );
    _focusNode.requestFocus();
  }

  Future<void> _toggleVoice() async {
    final voice = ref.read(voiceInputServiceProvider);
    if (_listening) {
      await voice.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final available = await voice.ensureAvailable();
    if (!available || !mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Голосовой ввод недоступен: проверьте разрешение на микрофон'),
        ),
      );
      return;
    }
    setState(() => _listening = true);
    await voice.startListening(
      onText: (spoken) {
        final base = _controller.text.isEmpty ? '' : '${_controller.text} ';
        _controller.text = '$base$spoken';
      },
      onStatus: (active) {
        if (mounted) setState(() => _listening = active);
      },
    );
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

  Future<void> _showOptions() async {
    final choice = await showModalBottomSheet<_OptionAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.alarm_add),
              title: const Text('Указать дату вручную'),
              onTap: () => Navigator.pop(ctx, _OptionAction.reminder),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Шаблон заметки'),
              onTap: () => Navigator.pop(ctx, _OptionAction.template),
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Выбрать категорию'),
              onTap: () => Navigator.pop(ctx, _OptionAction.category),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _OptionAction.reminder:
        await _pickManualReminder();
      case _OptionAction.template:
        await _pickTemplate();
      case _OptionAction.category:
        await _pickCategory();
    }
  }

  Future<void> _pickTemplate() async {
    final template = await showModalBottomSheet<NoteTemplate>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Шаблоны', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final t in NoteTemplates.all)
              ListTile(
                leading: const Icon(Icons.note_outlined, color: AppColors.gold),
                title: Text(t.title),
                subtitle: Text(t.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      ),
    );
    if (template != null) {
      _controller.text = template.text;
    }
  }

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<NoteCategory>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Категория', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            for (final c in NoteCategory.values)
              ListTile(
                leading: Icon(c.icon, color: AppColors.gold),
                title: Text(c.label),
                trailing: c == _suggestedCategory
                    ? const Icon(Icons.check, color: AppColors.gold)
                    : null,
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _manualCategory = picked);
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
    final category = _suggestedCategory;
    final settings = ref.watch(settingsProvider).valueOrNull ??
        const AppSettings();
    final aiActive = AiClientFactory.isConfigured(settings);

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
                if (aiActive)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome,
                            size: 14, color: AppColors.gold),
                        const SizedBox(width: 4),
                        Text(
                          'ИИ-распознавание активно',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.gold),
                        ),
                      ],
                    ),
                  ),
                if (_controller.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 6),
                    child: Row(
                      children: [
                        Icon(category.icon, size: 15, color: AppColors.gold),
                        const SizedBox(width: 4),
                        Text(
                          'Категория: ${category.label}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.gold),
                        ),
                      ],
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
                      tooltip: 'Голосовой ввод',
                      icon: Icon(
                        _listening ? Icons.mic : Icons.mic_none,
                        color: _listening ? AppColors.danger : null,
                      ),
                      onPressed: _toggleVoice,
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
                      onPressed: _showOptions,
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
enum _OptionAction { reminder, template, category }
