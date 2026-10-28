import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../models/note.dart';
import '../models/note_attachment.dart';
import '../models/note_category.dart';

class NotesNotifier extends AsyncNotifier<List<AppNote>> {
  @override
  Future<List<AppNote>> build() {
    return ref.read(notesRepositoryProvider).loadAll();
  }

  /// Создаёт заметку: парсит дату из текста, сохраняет, планирует напоминание.
  Future<AppNote> addFromText(
    String text, {
    bool isFamily = false,
    DateTime? reminderOverride,
    List<NoteAttachment> attachments = const [],
    NoteCategory? categoryOverride,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError('Заметка не может быть пустой');

    // Единая точка разбора: правила либо LLM (если включено в настройках),
    // с гарантированным фолбэком на правила внутри реализации.
    final ai = await ref.read(aiParserProvider).parse(trimmed);
    final reminder = reminderOverride ?? ai.reminderDate;
    final settings = ref.read(settingsProvider).valueOrNull;
    final authorName = settings?.profileName ?? 'Я';
    final category = categoryOverride ?? ai.category;

    final note = await ref.read(notesRepositoryProvider).add(
          id: ref.read(uuidProvider).v4(),
          text: trimmed,
          authorId: 'me',
          authorName: authorName,
          reminderAt: reminder,
          isFamily: isFamily,
          attachments: attachments,
          category: category,
        );
    state = AsyncData([note, ...?state.valueOrNull]);
    return note;
  }

  /// Ручная смена категории (ИИ-подсказку можно переопределить).
  Future<void> setCategory(AppNote note, NoteCategory category) =>
      updateNote(note.copyWith(category: category));

  /// Принудительная синхронизация: прогон через SyncService и снятие
  /// флага pendingSync у переданных заметок.
  Future<void> syncNow() async {
    final notes = state.valueOrNull ?? await future;
    await ref.read(syncServiceProvider).syncNow();
    final pending = notes.where((n) => n.pendingSync).map((n) => n.id).toList();
    if (pending.isNotEmpty) {
      await ref.read(notesRepositoryProvider).markSynced(pending);
      state = AsyncData([
        for (final n in notes)
          pending.contains(n.id) ? n.copyWith(pendingSync: false) : n,
      ]);
    }
  }

  // Имя updateNote вместо update: в riverpod 2.6+ у AsyncNotifierBase
  // уже есть метод update с другой сигнатурой.
  Future<void> updateNote(AppNote note) async {
    final updated = await ref.read(notesRepositoryProvider).update(note);
    final list = [...?state.valueOrNull];
    final i = list.indexWhere((n) => n.id == note.id);
    if (i != -1) list[i] = updated;
    state = AsyncData(list);
  }

  Future<void> remove(String id) async {
    await ref.read(notesRepositoryProvider).remove(id);
    state = AsyncData(
      [...?state.valueOrNull]..removeWhere((n) => n.id == id),
    );
  }

  Future<void> toggleDone(AppNote note) =>
      updateNote(note.copyWith(done: !note.done));

  Future<void> setReminder(AppNote note, DateTime? when) =>
      updateNote(note.copyWith(clearReminder: when == null, reminderAt: when));

  /// Перепланирует напоминания после перезапуска приложения.
  Future<void> rescheduleAll() async {
    final notes = state.valueOrNull ?? await future;
    await ref.read(notesRepositoryProvider).rescheduleAll(notes);
  }
}
