import '../../../core/services/json_store.dart';
import '../../../core/services/notification_service.dart';
import '../models/note.dart';
import '../models/note_attachment.dart';
import '../models/note_category.dart' show CategoryKeys;

/// Офлайн-first репозиторий заметок.
///
/// Все операции сначала пишутся в локальный JSON, затем планируется
/// локальное уведомление. Поле [AppNote.pendingSync] помечает данные,
/// которые облачный SyncService отправит на сервер (сейчас или потом —
/// при появлении сети, раздел 2.2 ТЗ).
class NotesRepository {
  final JsonStoreBase store;
  final NotificationService notifications;
  static const _fileName = 'notes.json';

  NotesRepository(this.store, this.notifications);

  Future<List<AppNote>> loadAll() async {
    final raw = await store.readList(_fileName);
    final notes = raw.map(AppNote.fromMap).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return notes;
  }

  Future<void> _persist(List<AppNote> notes) {
    return store.writeList(_fileName, notes.map((n) => n.toMap()).toList());
  }

  /// Перепланировать все будущие напоминания (вызывается при старте приложения).
  Future<void> rescheduleAll(List<AppNote> notes) async {
    await notifications.cancelAll();
    for (final note in notes) {
      if (note.reminderAt != null &&
          note.reminderAt!.isAfter(DateTime.now()) &&
          !note.done) {
        await _schedule(note);
      }
    }
  }

  Future<AppNote> add({
    required String id,
    required String text,
    required String authorId,
    required String authorName,
    DateTime? reminderAt,
    bool isFamily = false,
    List<NoteAttachment> attachments = const [],
    String categoryKey = CategoryKeys.general,
    bool aiAssisted = false,
  }) async {
    final notes = await loadAll();
    final note = AppNote(
      id: id,
      text: text,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      reminderAt: reminderAt,
      isFamily: isFamily,
      authorId: authorId,
      authorName: authorName,
      attachments: attachments,
      categoryKey: categoryKey,
      aiAssisted: aiAssisted,
    );
    notes.insert(0, note);
    await _persist(notes);
    await _schedule(note);
    return note;
  }

  Future<AppNote> update(AppNote updated) async {
    final notes = await loadAll();
    final index = notes.indexWhere((n) => n.id == updated.id);
    if (index == -1) throw StateError('Заметка ${updated.id} не найдена');
    notes[index] = updated.copyWith(updatedAt: DateTime.now(), pendingSync: true);
    await _persist(notes);

    await notifications.cancel(updated.id.hashCode);
    if (updated.reminderAt != null &&
        updated.reminderAt!.isAfter(DateTime.now()) &&
        !updated.done) {
      await _schedule(updated);
    }
    return notes[index];
  }

  Future<void> remove(String id) async {
    final notes = await loadAll();
    notes.removeWhere((n) => n.id == id);
    await _persist(notes);
    await notifications.cancel(id.hashCode);
  }

  /// Переносит все заметки одной категории в другую (используется при
  /// удалении пользовательской категории).
  Future<int> remapCategory(String oldKey, String newKey) async {
    final notes = await loadAll();
    final updated = [
      for (final n in notes)
        n.categoryKey == oldKey ? n.copyWith(categoryKey: newKey) : n,
    ];
    final changed = notes.where((n) => n.categoryKey == oldKey).length;
    if (changed > 0) await _persist(updated);
    return changed;
  }

  Future<void> markSynced(List<String> ids) async {
    final notes = await loadAll();
    var changed = false;
    for (var i = 0; i < notes.length; i++) {
      if (ids.contains(notes[i].id) && notes[i].pendingSync) {
        notes[i] = notes[i].copyWith(pendingSync: false);
        changed = true;
      }
    }
    if (changed) await _persist(notes);
  }

  Future<void> _schedule(AppNote note) async {
    final reminder = note.reminderAt;
    if (reminder == null) return;
    // Прошедшие напоминания не планируем (дублируем защиту сервиса,
    // чтобы поведение не зависело от реализации NotificationService).
    if (!reminder.isAfter(DateTime.now())) return;
    await notifications.schedule(
      id: note.id.hashCode,
      title: 'Напоминание Smart Notes',
      body: note.text.length > 120 ? '${note.text.substring(0, 120)}…' : note.text,
      when: reminder,
    );
  }
}
