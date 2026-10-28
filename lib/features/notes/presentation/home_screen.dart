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

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesNotifierProvider).valueOrNull ?? [];
    final dateFilter = ref.watch(homeDateFilterProvider);
    final query = ref.watch(homeSearchQueryProvider).toLowerCase();
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

    return SafeArea(
      child: Column(
        children: [
          const TodayHeader(),
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
                Text('Лента заметок',
                    style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
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
                decoration: const InputDecoration(
                  hintText: 'Поиск по заметкам…',
                ),
                onChanged: (v) =>
                    ref.read(homeSearchQueryProvider.notifier).state = v,
              ),
            ),
          Expanded(
            child: NoteFeed(
              notes: visible,
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
