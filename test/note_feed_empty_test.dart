import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notes/features/notes/presentation/widgets/note_feed.dart';

void main() {
  Widget host(NoteFeed feed) => ProviderScope(
        child: MaterialApp(home: Scaffold(body: feed)),
      );

  testWidgets('Первая заметка: подсказка указывает на ввод выше', (tester) async {
    await tester.pumpWidget(host(NoteFeed(notes: const [], onOpen: (_) {})));
    expect(find.textContaining('Напишите выше'), findsOneWidget);
    expect(find.text('Сбросить поиск и фильтры'), findsNothing);
  });

  testWidgets('Нет результатов: доступен сброс фильтров', (tester) async {
    var resets = 0;
    await tester.pumpWidget(host(NoteFeed(
      notes: const [],
      onOpen: (_) {},
      emptyText: 'Ничего не найдено',
      onResetFilters: () => resets++,
    )));
    expect(find.text('Ничего не найдено'), findsOneWidget);
    await tester.tap(find.text('Сбросить поиск и фильтры'));
    expect(resets, 1);
  });

  testWidgets('Семейная пустая лента не обещает обмен между телефонами', (tester) async {
    await tester.pumpWidget(host(NoteFeed(
      notes: const [], onOpen: (_) {}, showAuthor: true,
    )));
    expect(find.textContaining('в поле выше'), findsOneWidget);
    expect(find.textContaining('ниже'), findsNothing);
  });
}
