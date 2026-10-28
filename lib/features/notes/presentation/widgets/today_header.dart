import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../models/note.dart';
import '../note_detail_screen.dart';
import 'mini_calendar.dart';

/// Блок "Сегодня" (раздел 2.1 ТЗ):
/// свёрнут — не менее 15% экрана, свайп вверх разворачивает календарь,
/// вниз — сворачивает. Тап по строке дела открывает заметку; календарь
/// разворачивается только тапом по шапке (заголовок + шеврон).
class TodayHeader extends ConsumerStatefulWidget {
  const TodayHeader({super.key});

  @override
  ConsumerState<TodayHeader> createState() => _TodayHeaderState();
}

class _TodayHeaderState extends ConsumerState<TodayHeader> {
  bool _expanded = false;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = ref.watch(notesNotifierProvider).valueOrNull ?? [];
    final filter = ref.watch(homeDateFilterProvider);
    final screenHeight = MediaQuery.sizeOf(context).height;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final urgent = notes
        .where((n) =>
            n.reminderAt != null &&
            !n.done &&
            (n.reminderAt!.isAfter(now) || _sameDay(n.reminderAt!, now)))
        .toList()
      ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
    final todays = urgent.where((n) => _sameDay(n.reminderAt!, today)).toList();

    final markedDays = <DateTime>{
      for (final n in notes)
        if (n.reminderAt != null)
          DateTime(n.reminderAt!.year, n.reminderAt!.month, n.reminderAt!.day),
    };

    final collapsedMinHeight = screenHeight * 0.15;
    final expandedHeight = screenHeight * 0.46;

    return GestureDetector(
      // Свайп по всей карточке разворачивает/сворачивает календарь,
      // но тапов по делам больше не перехватываем.
      onVerticalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) setState(() => _expanded = true);
        if (v > 200) setState(() => _expanded = false);
      },
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        // AnimatedSize анимирует смену размеров сам: анимация constraints
        // невозможна (конечный maxHeight нельзя интерполировать с бесконечным).
        child: Container(
        // В свёрнутом виде карточка сама растёт под содержимое (минимум 15%),
        // ничего не обрезается; в развёрнутом — фиксированная высота со скроллом.
        constraints: _expanded
            ? BoxConstraints(
                minHeight: expandedHeight, maxHeight: expandedHeight)
            : BoxConstraints(minHeight: collapsedMinHeight),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          boxShadow: const [
            BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: SingleChildScrollView(
          // В развёрнутом виде календарю разрешён скролл, чтобы не было overflow;
          // в сжатом (клавиатура) состоянии дела тоже можно проскроллить внутри карточки.
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Только шапка переключает календарь — явный тап-таргет с шевроном.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleExpanded,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Сегодня', style: theme.textTheme.headlineMedium),
                          const SizedBox(height: 2),
                          Text(
                            'Дел на день: ${todays.length} · всего срочных: ${urgent.length}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _expanded ? 'Свернуть календарь' : 'Открыть календарь',
                      icon: Icon(
                        _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                        color: AppColors.gold,
                      ),
                      onPressed: _toggleExpanded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (!_expanded) ...[
                if (urgent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Срочных дел нет — всё по плану.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ...urgent.take(3).map((n) => _UrgentLine(note: n)),
                if (urgent.length > 3)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleExpanded,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Ещё ${urgent.length - 3} — открыть календарь',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.gold),
                      ),
                    ),
                  ),
              ],
              if (_expanded) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(() => _visibleMonth =
                          DateTime(_visibleMonth.year, _visibleMonth.month - 1)),
                    ),
                    Text(DateFormatter.dayMonth(_visibleMonth),
                        style: theme.textTheme.titleLarge),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(() => _visibleMonth =
                          DateTime(_visibleMonth.year, _visibleMonth.month + 1)),
                    ),
                  ],
                ),
                MiniCalendar(
                  month: _visibleMonth,
                  selected: filter,
                  markedDays: markedDays,
                  onSelect: (d) =>
                      ref.read(homeDateFilterProvider.notifier).state = d,
                ),
                if (filter != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Chip(
                      label: Text('Фильтр: ${DateFormatter.dayMonth(filter)}'),
                      onDeleted: () =>
                          ref.read(homeDateFilterProvider.notifier).state = null,
                    ),
                  ),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// Строка срочного дела в блоке "Сегодня".
/// Тап по тексту открывает заметку, тап по кружку — отмечает выполнение.
class _UrgentLine extends ConsumerWidget {
  final AppNote note;
  const _UrgentLine({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () =>
                ref.read(notesNotifierProvider.notifier).toggleDone(note),
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Icon(
                note.done
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 18,
                color: note.done ? AppColors.success : AppColors.gold,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NoteDetailScreen(noteId: note.id),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      decoration:
                          note.done ? TextDecoration.lineThrough : null,
                      color: note.done
                          ? theme.textTheme.bodySmall?.color
                          : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormatter.timeOnly(note.reminderAt!),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.gold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
