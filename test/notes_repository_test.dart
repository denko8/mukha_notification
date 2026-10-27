import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notes/core/services/json_store.dart';
import 'package:smart_notes/core/services/notification_service.dart';
import 'package:smart_notes/features/notes/data/notes_repository.dart';

void main() {
  late Directory dir;
  late JsonStore store;
  late NoopNotificationService notifications;
  late NotesRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('smart_notes_test_');
    store = JsonStore(dir);
    notifications = NoopNotificationService();
    repo = NotesRepository(store, notifications);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('заметка сохраняется и читается из хранилища', () async {
    await repo.add(
      id: 'n1',
      text: 'Позвонить Диме завтра в 14:00',
      authorId: 'me',
      authorName: 'Я',
      reminderAt: DateTime(2024, 12, 6, 14, 0),
    );

    final reloaded = await NotesRepository(
      JsonStore(dir),
      NoopNotificationService(),
    ).loadAll();

    expect(reloaded, hasLength(1));
    expect(reloaded.first.text, 'Позвонить Диме завтра в 14:00');
    expect(reloaded.first.reminderAt, DateTime(2024, 12, 6, 14, 0));
    expect(reloaded.first.pendingSync, isTrue);
  });

  test('при создании заметки с будущим напоминанием планируется уведомление',
      () async {
    await repo.add(
      id: 'n2',
      text: 'Встреча',
      authorId: 'me',
      authorName: 'Я',
      reminderAt: DateTime.now().add(const Duration(hours: 2)),
    );
    expect(notifications.scheduled, hasLength(1));
  });

  test('удаление отменяет уведомление и убирает заметку', () async {
    await repo.add(
      id: 'n3',
      text: 'На удаление',
      authorId: 'me',
      authorName: 'Я',
      reminderAt: DateTime.now().add(const Duration(hours: 1)),
    );
    await repo.remove('n3');

    final notes = await repo.loadAll();
    expect(notes, isEmpty);
    expect(notifications.cancelled, contains('n3'.hashCode));
  });

  test('обновление меняет текст и помечает заметку на синхронизацию', () async {
    final note = await repo.add(
      id: 'n4',
      text: 'Старый текст',
      authorId: 'me',
      authorName: 'Я',
    );
    await repo.update(note.copyWith(text: 'Новый текст', pendingSync: false));

    final notes = await repo.loadAll();
    expect(notes.single.text, 'Новый текст');
    expect(notes.single.pendingSync, isTrue);
  });

  test('прошедшее напоминание не планируется', () async {
    await repo.add(
      id: 'n5',
      text: 'Прошлое',
      authorId: 'me',
      authorName: 'Я',
      reminderAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
    expect(notifications.scheduled, isEmpty);
  });
}
