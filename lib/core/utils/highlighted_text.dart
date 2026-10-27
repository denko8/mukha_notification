import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'date_parser.dart';

/// Строит [TextSpan], подсвечивая найденные даты золотистым цветом (раздел 2.1 ТЗ).
///
/// В режиме [tappable] по подсвеченной дате можно тапнуть —
/// используется на экране деталей для редактирования напоминания.
TextSpan buildHighlightedSpan(
  String text,
  List<HighlightSpan> spans, {
  required TextStyle baseStyle,
  bool tappable = false,
  VoidCallback? onDateTap,
}) {
  if (spans.isEmpty) return TextSpan(text: text, style: baseStyle);

  final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
  final children = <InlineSpan>[];
  var cursor = 0;

  for (final span in sorted) {
    if (span.start > cursor) {
      children.add(TextSpan(text: text.substring(cursor, span.start), style: baseStyle));
    }
    final goldStyle = baseStyle.copyWith(
      color: AppColors.gold,
      fontWeight: FontWeight.w600,
    );
    children.add(
      TextSpan(
        text: text.substring(span.start, span.end),
        style: goldStyle,
        recognizer: tappable
            ? (TapGestureRecognizer()..onTap = onDateTap)
            : null,
      ),
    );
    cursor = span.end;
  }
  if (cursor < text.length) {
    children.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return TextSpan(style: baseStyle, children: children);
}
