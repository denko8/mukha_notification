// Перенести в lib/core/services/firebase_attachment_storage.dart
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../features/notes/models/note_attachment.dart';

/// Загрузка вложений в Firebase Storage с заменой локального пути на URL.
class FirebaseAttachmentStorage {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<NoteAttachment> upload(NoteAttachment attachment, String noteId) async {
    final uid = _auth.currentUser?.uid ?? 'anonymous';
    final ref = _storage.ref('users/$uid/notes/$noteId/${attachment.id}_${attachment.name}');
    await ref.putFile(File(attachment.path));
    final url = await ref.getDownloadURL();
    return NoteAttachment(
      id: attachment.id,
      type: attachment.type,
      path: url, // после миграции path хранит публичный URL
      name: attachment.name,
      createdAt: attachment.createdAt,
    );
  }

  Future<void> delete(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {
      // Файл уже удалён или URL не storage-схемы.
    }
  }
}
