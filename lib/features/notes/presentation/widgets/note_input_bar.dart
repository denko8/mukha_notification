import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/date_parser.dart';
import '../../../../core/utils/highlighted_text.dart';
import '../../../../core/services/voice_input_service.dart';
import '../../../../core/services/voice_model_service.dart';
import '../../../ai/llm/ai_client_factory.dart';
import '../../../settings/models/app_settings.dart';
import '../../models/note_attachment.dart';
import '../../models/note_category.dart' show CategoryKeys;
import '../../utils/attachment_picker.dart';
import '../../utils/category_catalog.dart';
import '../../utils/note_classifier.dart';
import '../../utils/note_templates.dart';
import 'category_picker_sheet.dart';

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

class _NoteInputBarState extends ConsumerState<NoteInputBar>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final List<NoteAttachment> _attachments = [];
  DateParseResult _parsed = DateParseResult.empty;
  DateTime? _manualReminder;
  String? _manualCategoryKey;
  late bool _isFamily = widget.forceFamily;
  bool _listening = false;
  // Движок готовит модель/распознаватель (1–3 сек) — показываем
  // спиннер вместо иконки, чтобы нажатие не выглядело «мёртвым».
  bool _voiceBusy = false;
  // Текст, набранный руками до начала сессии: распознанное подставляется
  // суффиксом и заменяется целиком (Vosk отдаёт нарастающий partial).
  String _voiceBase = '';
  // Пауза в речи, после которой заметка автоматически сохраняется.
  static const Duration _silenceAutoSave = Duration(seconds: 3);
  Timer? _silenceTimer;
  // Пульс красной точки-индикатора записи.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _pulse.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Перезапускает отсчёт тишины: вызывается на каждом распознанном
  /// фрагменте. Срабатывает только во время активной записи.
  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_silenceAutoSave, _onSilenceTimeout);
  }

  void _cancelSilenceTimer() => _silenceTimer?.cancel();

  /// Тишина дольше [_silenceAutoSave]: есть текст — сохраняем заметку
  /// и гасим микрофон; текста нет — просто выключаем запись.
  Future<void> _onSilenceTimeout() async {
    if (!mounted || !_listening) return;
    _cancelSilenceTimer();
    await ref.read(voiceInputServiceProvider).stopListening();
    if (!mounted) return;
    setState(() => _listening = false);
    final spoken = _controller.text.trim();
    if (spoken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ничего не расслышал — запись выключена'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await _save();
  }

  void _onControllerChanged() => setState(_recomputeHints);

  void _recomputeHints() {
    _parsed = NaturalDateParser().parse(_controller.text);
  }

  String _suggestedCategoryKey(AppSettings settings) =>
      _manualCategoryKey ??
      NoteClassifier.classifyKey(_controller.text, settings.customCategories);

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала введите текст заметки')),
      );
      return;
    }
    // Сохранение всегда завершает голосовую сессию: гасим таймер
    // тишины и микрофон, иначе запись продолжает висеть в фоне.
    _cancelSilenceTimer();
    if (_listening) {
      await ref.read(voiceInputServiceProvider).stopListening();
      if (mounted) setState(() => _listening = false);
    }
    _voiceBase = '';
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const AppSettings();
    await ref.read(notesNotifierProvider.notifier).addFromText(
          text,
          isFamily: _isFamily,
          reminderOverride: _manualReminder,
          attachments: List.of(_attachments),
          categoryOverride: _suggestedCategoryKey(settings),
        );

    // Звук "тинь" + тактильный отклик (кастомный ассет подключим в v1.1).
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.mediumImpact();
    if (!mounted) return;

    _controller.clear();
    setState(() {
      _attachments.clear();
      _manualReminder = null;
      _manualCategoryKey = null;
      _parsed = DateParseResult.empty;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Заметка сохранена'),
        duration: Duration(seconds: 1),
      ),
    );
    // Клавиатура закрывается после отправки: снимаем фокус с поля.
    // Действует и для ручной отправки, и для авто-сохранения голосом —
    // оба пути сохраняются через _save().
    _focusNode.unfocus();
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      _cancelSilenceTimer();
      await ref.read(voiceInputServiceProvider).stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final modelState = ref.read(voiceModelServiceProvider);
    if (!modelState.isReady) {
      await _showVoiceModelSheet();
      return;
    }
    await _startVoiceSession();
  }

  /// Одноразовая загрузка офлайн-модели: BottomSheet с объяснением,
  /// живым прогрессом в МБ и повтором при ошибке.
  Future<void> _showVoiceModelSheet() async {
    final modelService = ref.read(voiceModelServiceProvider.notifier);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            // Модель готова — закрываем шит, сессия стартует ниже.
            ref.listen<VoiceModelState>(voiceModelServiceProvider,
                (prev, next) {
              if (next.phase == VoiceModelPhase.ready &&
                  Navigator.of(sheetContext).canPop()) {
                Navigator.of(sheetContext).pop();
              }
            });
            final state = ref.watch(voiceModelServiceProvider);
            final downloading =
                state.phase == VoiceModelPhase.downloading ||
                    state.phase == VoiceModelPhase.extracting;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mic_none, color: AppColors.gold),
                        const SizedBox(width: 10),
                        Text('Голосовой ввод',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Нужно один раз скачать офлайн-модель русской речи '
                      'около 45 МБ. После этого диктовка работает без '
                      'интернета и без Google-сервисов.',
                    ),
                    const SizedBox(height: 16),
                    if (state.phase == VoiceModelPhase.error) ...[
                      Text(
                        'Не удалось скачать: ${state.error ?? 'ошибка сети'}. '
                        'Проверьте интернет и попробуйте снова.',
                        style: TextStyle(color: AppColors.danger),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (downloading) ...[
                      LinearProgressIndicator(
                        value: state.phase == VoiceModelPhase.extracting
                            ? null
                            : (state.progress > 0 ? state.progress : null),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.phase == VoiceModelPhase.extracting
                            ? 'Распаковка модели…'
                            : 'Скачивание: ${_mb(state.receivedBytes)}'
                                '${state.totalBytes > 0 ? ' из ${_mb(state.totalBytes)}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: Icon(state.phase == VoiceModelPhase.error
                            ? Icons.refresh
                            : Icons.download_rounded),
                        label: Text(downloading
                            ? 'Идёт загрузка…'
                            : state.phase == VoiceModelPhase.error
                                ? 'Повторить'
                                : 'Скачать модель'),
                        onPressed: downloading
                            ? null
                            : () => modelService.download(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // Модель докачалась, пока шит был открыт, — сразу стартуем сессию.
    if (mounted && ref.read(voiceModelServiceProvider).isReady) {
      await _startVoiceSession();
    }
  }

  Future<void> _startVoiceSession() async {
    final voice = ref.read(voiceInputServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final check = await voice.ensureAvailable();
    if (!check.ok || !mounted) {
      if (check.availability == VoiceAvailability.permissionDenied) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Нет доступа к микрофону — включите его в настройках '
              'приложения, чтобы диктовать заметки.',
            ),
            action: SnackBarAction(
              label: 'Настройки',
              onPressed: openAppSettings,
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Голосовой ввод недоступен'
              '${check.technicalDetails != null ? ': ${check.technicalDetails}' : ''}',
            ),
          ),
        );
      }
      return;
    }

    _voiceBase = _controller.text.trim();
    setState(() {
      _voiceBusy = true;
      _listening = true;
    });
    await voice.startListening(
      onText: (spoken) {
        final prefix = _voiceBase.isEmpty ? '' : '$_voiceBase ';
        _controller.text = '$prefix$spoken';
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
        // Каждая новая порция речи отодвигает авто-сохранение.
        _armSilenceTimer();
      },
      onStatus: (active) {
        if (!mounted) return;
        setState(() {
          _voiceBusy = false;
          _listening = active;
        });
        if (!active) _cancelSilenceTimer();
      },
      onError: (message) {
        if (!mounted) return;
        _cancelSilenceTimer();
        setState(() {
          _voiceBusy = false;
          _listening = false;
        });
        messenger.showSnackBar(
          SnackBar(content: Text('Ошибка распознавания: $message')),
        );
      },
    );
    if (mounted) {
      setState(() => _voiceBusy = false);
      // Если пользователь молчит с самого старта — через 3 секунды
      // запись аккуратно выключится без сохранения пустой заметки.
      if (_listening) _armSilenceTimer();
    }
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';

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
                leading: Icon(Icons.note_outlined, color: AppColors.gold),
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
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const AppSettings();
    final catalog = CategoryCatalog(settings.customCategories);
    final picked = await showCategoryPickerSheet(
      context,
      catalog: catalog,
      selectedKey: _suggestedCategoryKey(settings),
    );
    if (picked == null || !mounted) return;

    if (picked.createRequested) {
      final input = await showCustomCategoryDialog(context, catalog: catalog);
      if (input == null || !mounted) return;
      final created = await ref
          .read(settingsProvider.notifier)
          .addCustomCategory(label: input.label, keywords: input.keywords);
      if (mounted) {
        setState(() =>
            _manualCategoryKey = CategoryKeys.forCustom(created.id));
      }
      return;
    }
    setState(() => _manualCategoryKey = picked.categoryKey);
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
    final settings = ref.watch(settingsProvider).valueOrNull ??
        const AppSettings();
    final catalog = CategoryCatalog(settings.customCategories);
    final categoryKey = _suggestedCategoryKey(settings);
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
                         Icon(Icons.auto_awesome,
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
                        Icon(catalog.iconOf(categoryKey),
                            size: 15, color: AppColors.gold),
                        const SizedBox(width: 4),
                        Text(
                          'Категория: ${catalog.labelOf(categoryKey)}',
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
                        Icon(Icons.alarm, size: 15, color: AppColors.gold),
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
                if (_listening)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Row(
                      children: [
                        FadeTransition(
                          opacity: _pulse,
                          child: const Icon(
                            Icons.fiber_manual_record,
                            size: 12,
                            color: AppColors.danger,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Идёт запись. Пауза 3 секунды — заметка '
                            'сохранится сама, микрофон выключится.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 16),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Голосовой ввод',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                          minWidth: 40, minHeight: 40),
                      padding: const EdgeInsets.all(6),
                      icon: _voiceBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _listening ? Icons.mic : Icons.mic_none,
                              color: _listening ? AppColors.danger : null,
                            ),
                      onPressed:
                          _voiceBusy ? null : _toggleVoice,
                    ),
                    IconButton(
                      tooltip: 'Прикрепить файл',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                          minWidth: 40, minHeight: 40),
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(Icons.attach_file),
                      color: theme.colorScheme.onSurface,
                      onPressed: _showAttachSheet,
                    ),
                    IconButton(
                      tooltip: 'Опции',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                          minWidth: 40, minHeight: 40),
                      padding: const EdgeInsets.all(6),
                      icon: const Icon(Icons.add_circle_outline),
                      color: theme.colorScheme.onSurface,
                      onPressed: _showOptions,
                    ),
                    if (widget.showFamilyToggle) ...[
                      // Flexible занимает всё место после кнопок, а
                      // FittedBox(scaleDown) ужимает содержимое, если оно
                      // не влезает: RenderFlex overflow на узких экранах
                      // исключён в принципе.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Tooltip(
                            message:
                                'Включите, чтобы заметку видели все члены семьи',
                            child: GestureDetector(
                              // Тап по иконке/подписи тоже переключает —
                              // удобнее, чем попадать в маленький Switch.
                              onTap: widget.forceFamily
                                  ? null
                                  : () => setState(
                                      () => _isFamily = !_isFamily),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.groups_outlined,
                                    size: 16,
                                    color: _isFamily
                                        ? AppColors.gold
                                        : theme.colorScheme.onSurface
                                            .withValues(alpha: 0.65),
                                  ),
                                  const SizedBox(width: 3),
                                  // Внутри FittedBox ширина не ограничена,
                                  // поэтому softWrap:false вместо Flexible.
                                  Text(
                                    'Семейная',
                                    softWrap: false,
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: _isFamily
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color:
                                          _isFamily ? AppColors.gold : null,
                                    ),
                                  ),
                                  Switch(
                                    value: _isFamily,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    onChanged: widget.forceFamily
                                        ? null
                                        : (v) =>
                                            setState(() => _isFamily = v),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    IconButton(
                      tooltip: 'Сохранить',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                          minWidth: 40, minHeight: 40),
                      padding: const EdgeInsets.all(6),
                      icon: Icon(Icons.send, color: AppColors.gold),
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
