import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_parser.dart';
import '../models/note.dart';

class NoteEditScreen extends ConsumerStatefulWidget {
  final String noteId;

  const NoteEditScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends ConsumerState<NoteEditScreen> {
  late final TextEditingController _controller;
  bool _initialized = false;

  AppNote? _find(List<AppNote> notes) {
    for (final n in notes) {
      if (n.id == widget.noteId) return n;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesNotifierProvider).valueOrNull ?? [];
    final note = _find(notes);
    if (note == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_initialized) {
      _controller = TextEditingController(text: note.text);
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактирование'),
        actions: [
          TextButton(
            onPressed: () async {
              final text = _controller.text.trim();
              if (text.isEmpty) return;
              // Если в новом тексте появилась дата — обновляем напоминание,
              // иначе сохраняем ранее установленное.
              final parsed = NaturalDateParser().parse(text).reminderDate;
              final updated = note.copyWith(
                text: text,
                reminderAt: parsed ?? note.reminderAt,
                clearReminder: parsed == null && note.reminderAt == null,
              );
              await ref.read(notesNotifierProvider.notifier).updateNote(updated);
              if (context.mounted) Navigator.of(context).pop();
            },
            child:  Text('Сохранить',
                style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          maxLines: null,
          autofocus: true,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: const InputDecoration(hintText: 'Текст заметки'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_initialized) _controller.dispose();
    super.dispose();
  }
}
