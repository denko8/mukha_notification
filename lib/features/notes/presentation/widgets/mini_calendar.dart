import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Компактный месяц для развернутого блока "Сегодня".
class MiniCalendar extends StatelessWidget {
  final DateTime month;
  final DateTime? selected;
  final Set<DateTime> markedDays;
  final ValueChanged<DateTime> onSelect;

  const MiniCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.markedDays,
    required this.onSelect,
  });

  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1; // понедельник = 1 -> 0 пустых
    final today = DateTime.now();
    final cells = <Widget>[];

    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final isSelected = selected != null && _sameDay(date, selected!);
      final isToday = _sameDay(date, today);
      final hasNotes = markedDays.any((m) => _sameDay(m, date));

      cells.add(
        GestureDetector(
          onTap: () => onSelect(date),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? AppColors.gold : null,
              shape: BoxShape.circle,
              border: isToday && !isSelected
                  ? Border.all(color: AppColors.gold, width: 1.5)
                  : null,
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$d',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isSelected
                        ? Colors.white
                        : (isToday ? AppColors.gold : null),
                    fontWeight: isToday || isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                if (hasNotes)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? Colors.white : AppColors.gold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final w in _weekdays)
              Text(w, style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cells,
        ),
      ],
    );
  }
}
