import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../models/note.dart';
import 'mini_calendar.dart';

/// Блок "Сегодня" (раздел 2.1 ТЗ):
/// свёрнут — 15% экрана, свайп вверх разворачивает календарь, вниз — сворачивает.
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

    return GestureDetector(
      onVerticalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) setState(() => _expanded = true);
        if (v > 200) setState(() => _expanded = false);
      },
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: _expanded ? screenHeight * 0.46 : screenHeight * 0.15,
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
          // В развёрнутом виде календарю разрешён скролл, чтобы не было overflow.
          physics: _expanded
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                  Icon(
                    _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    color: AppColors.gold,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!_expanded)
                ...urgent.take(3).map((n) => _UrgentLine(note: n)),
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
    );
  }
}

class _UrgentLine extends StatelessWidget {
  final AppNote note;
  const _UrgentLine({required this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.check_box_outline_blank, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              note.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            '(${DateFormatter.timeOnly(note.reminderAt!)})',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.gold),
          ),
        ],
      ),
    );
  }
}
