import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../notes/presentation/note_detail_screen.dart';
import '../../notes/presentation/widgets/note_feed.dart';
import '../../notes/presentation/widgets/note_input_bar.dart';
import '../models/family_member.dart';
import 'widgets/invite_dialog.dart';

class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({super.key});

  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  StreamSubscription<String>? _inviteSub;

  @override
  void initState() {
    super.initState();
    _inviteSub = ref.read(deepLinkServiceProvider).inviteTokens.listen((token) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => JoinInviteDialog(initialToken: token),
      );
    });
  }

  @override
  void dispose() {
    _inviteSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = ref.watch(familyNotifierProvider).valueOrNull ?? [];
    final notes = ref.watch(notesNotifierProvider).valueOrNull ?? [];
    final authorFilter = ref.watch(familyAuthorFilterProvider);

    var familyNotes = notes.where((n) => n.isFamily).toList();
    if (authorFilter != null) {
      familyNotes =
          familyNotes.where((n) => n.authorId == authorFilter).toList();
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Лёгкая шапка: мелкий muted-заголовок + текстовая кнопка
          // вместо крупного ElevatedButton.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
            child: Row(
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: 17,
                  color: theme.textTheme.bodySmall?.color,
                ),
                const SizedBox(width: 6),
                Text(
                  'Семья',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.person_add_alt, size: 17),
                  label: const Text('Пригласить'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const InviteDialog(),
                  ),
                ),
              ],
            ),
          ),
          if (members.isNotEmpty)
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: members.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _MemberAvatar(
                  member: members[i],
                  selected: authorFilter == members[i].id,
                  onTap: () {
                    final notifier =
                        ref.read(familyAuthorFilterProvider.notifier);
                    notifier.state = authorFilter == members[i].id
                        ? null
                        : members[i].id;
                  },
                ),
              ),
            ),
          if (authorFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextButton.icon(
                icon: const Icon(Icons.filter_alt_off, size: 16),
                label: const Text('Сбросить фильтр'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.gold,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () =>
                    ref.read(familyAuthorFilterProvider.notifier).state =
                        null,
              ),
            ),
          const NoteInputBar(forceFamily: true, showFamilyToggle: false),
          Expanded(
            child: NoteFeed(
              notes: familyNotes,
              showAuthor: true,
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

class _MemberAvatar extends StatelessWidget {
  final FamilyMember member;
  final bool selected;
  final VoidCallback onTap;

  const _MemberAvatar({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Без тени: только тонкое золотое кольцо выбора — легче визуально.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: member.isMe ? AppColors.gold : theme.cardTheme.color,
              border: Border.all(
                color: selected ? AppColors.gold : Colors.transparent,
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              member.initial,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 14,
                color: member.isMe ? Colors.white : AppColors.gold,
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 52,
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                height: 1.2,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
