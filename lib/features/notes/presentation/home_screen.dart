import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import 'note_detail_screen.dart';
import 'widgets/category_filter.dart';
import 'widgets/note_feed.dart';
import 'widgets/note_input_bar.dart';
import 'widgets/today_header.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _searching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _searchController.clear();
    ref.read(homeSearchQueryProvider.notifier).state = '';
    ref.read(homeDateFilterProvider.notifier).state = null;
    ref.read(homeCategoryFilterProvider.notifier).state = null;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(notesNotifierProvider);
    final notes = notesState.valueOrNull ?? [];
    final dateFilter = ref.watch(homeDateFilterProvider);
    final query = ref.watch(homeSearchQueryProvider).trim().toLowerCase();
    final categoryFilter = ref.watch(homeCategoryFilterProvider);

    var visible = notes.where((n) => !n.isFamily).toList();
    if (dateFilter != null) {
      visible = visible
          .where((n) =>
              n.reminderAt != null && _sameDay(n.reminderAt!, dateFilter))
          .toList();
    }
    if (categoryFilter != null) {
      visible =
          visible.where((n) => n.categoryKey == categoryFilter).toList();
    }
    if (query.isNotEmpty) {
      visible = visible.where((n) => n.text.toLowerCase().contains(query)).toList();
    }

    final hasFilters = query.isNotEmpty || dateFilter != null || categoryFilter != null;

    return SafeArea(
      child: Column(
        children: [
          // Flexible: при открытой клавиатуре высота экрана падает почти вдвое,
          // и блок «Сегодня» сжимается под доступное место вместо overflow колонки.
          const Flexible(child: TodayHeader()),
          const NoteInputBar(),
          CategoryFilter(
            selected: categoryFilter,
            onChanged: (c) =>
                ref.read(homeCategoryFilterProvider.notifier).state = c,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text('Лента заметок',
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: _searching ? 'Закрыть поиск' : 'Поиск по заметкам',
                  icon: Icon(_searching ? Icons.search_off : Icons.search,
                      color: AppColors.gold),
                  onPressed: () {
                    setState(() => _searching = !_searching);
                    if (!_searching) {
                      _searchController.clear();
                      ref.read(homeSearchQueryProvider.notifier).state = '';
                    }
                  },
                ),
              ],
            ),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(
                  hintText: 'Найти в тексте заметок',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty ? null : IconButton(
                    tooltip: 'Очистить поиск',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(homeSearchQueryProvider.notifier).state = '';
                    },
                  ),
                ),
                onChanged: (v) =>
                    ref.read(homeSearchQueryProvider.notifier).state = v,
              ),
            ),
          if (hasFilters)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: Text('Найдено: ${visible.length} · Сбросить фильтры'),
                ),
              ),
            ),
          Expanded(
            child: notesState.hasError
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Не удалось загрузить заметки. Попробуйте ещё раз.',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => ref.invalidate(notesNotifierProvider),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  )
                : notesState.isLoading && notesState.valueOrNull == null
                    ? const Center(child: CircularProgressIndicator())
                    : NoteFeed(
              notes: visible,
              emptyText: hasFilters
                  ? 'По этим условиям ничего не найдено.\nПопробуйте другое слово или сбросьте фильтры.'
                  : null,
              onResetFilters: hasFilters ? _resetFilters : null,
              onOpen: (note) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NoteDetailScreen(noteId: note.id),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
