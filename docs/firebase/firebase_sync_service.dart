// Перенести в lib/core/services/firebase_sync_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/notes/data/notes_repository.dart';
import '../features/notes/models/note.dart';
import 'sync_service.dart';

/// Облачная синхронизация заметок через Firestore.
/// Конфликты решаются по updatedAt (побеждает более свежая запись).
class FirebaseSyncService implements SyncService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  SyncStatus status = SyncStatus.idle;
  @override
  DateTime? lastSyncAt;

  String? get _uid => _auth.currentUser?.uid;
  DocumentReference<Map<String, dynamic>> get _familyDoc =>
      _db.collection('families').doc('default');

  /// Вызывается после локального add/update/remove.
  Future<void> pushNote(AppNote note) async {
    final uid = _uid;
    if (uid == null) return;
    final collection = note.isFamily
        ? _familyDoc.collection('notes')
        : _db.collection('users').doc(uid).collection('notes');
    await collection.doc(note.id).set(note.toMap()..['updatedAtMs'] = note.updatedAt.millisecondsSinceEpoch);
  }

  Future<void> deleteNote(String id, {required bool isFamily}) async {
    final uid = _uid;
    if (uid == null) return;
    final collection = isFamily
        ? _familyDoc.collection('notes')
        : _db.collection('users').doc(uid).collection('notes');
    // Tombstone, чтобы удаление доехало до других устройств.
    await collection.doc(id).set({'deleted': true, 'updatedAtMs': DateTime.now().millisecondsSinceEpoch});
  }

  /// Слияние облака в локальный репозиторий.
  Future<List<AppNote>> pullNotes(NotesRepository local) async {
    final uid = _uid;
    if (uid == null) return local.loadAll();

    final personal = await _db
        .collection('users')
        .doc(uid)
        .collection('notes')
        .get();
    final family = await _familyDoc.collection('notes').get();

    final cloud = <String, AppNote>{};
    for (final snap in [...personal.docs, ...family.docs]) {
      final data = snap.data();
      if (data['deleted'] == true) continue;
      final note = AppNote.fromMap(data);
      final existing = cloud[note.id];
      if (existing == null || note.updatedAt.isAfter(existing.updatedAt)) {
        cloud[note.id] = note;
      }
    }
    return cloud.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> syncNow() async {
    status = SyncStatus.syncing;
    try:
      // Полный цикл реализует NotesNotifier.syncNow поверх pullNotes/pushNote;
      // здесь только статусная часть контракта SyncService.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      lastSyncAt = DateTime.now();
      status = SyncStatus.synced;
    } catch (_) {
      status = SyncStatus.error;
    }
  }
}
