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
    final members = ref.watch(familyNotifierProvider).valueOrNull ?? [];
    final notes = ref.watch(notesNotifierProvider).valueOrNull ?? [];
    final authorFilter = ref.watch(familyAuthorFilterProvider);

    var familyNotes = notes.where((n) => n.isFamily).toList();
    if (authorFilter != null) {
      familyNotes = familyNotes.where((n) => n.authorId == authorFilter).toList();
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text('Твоя семья', style: Theme.of(context).textTheme.headlineMedium),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('Пригласить'),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const InviteDialog(),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              itemCount: members.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _MemberAvatar(
                member: members[i],
                selected: authorFilter == members[i].id,
                onTap: () {
                  final notifier = ref.read(familyAuthorFilterProvider.notifier);
                  notifier.state =
                      authorFilter == members[i].id ? null : members[i].id;
                },
              ),
            ),
          ),
          if (authorFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Chip(
                label: const Text('Фильтр по участнику'),
                onDeleted: () =>
                    ref.read(familyAuthorFilterProvider.notifier).state = null,
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: member.isMe ? AppColors.gold : theme.cardTheme.color,
              border: Border.all(
                color: selected ? AppColors.gold : Colors.transparent,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              member.initial,
              style: theme.textTheme.titleLarge?.copyWith(
                color: member.isMe ? Colors.white : AppColors.gold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 56,
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
