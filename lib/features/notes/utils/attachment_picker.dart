import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/note_attachment.dart';

/// Выбор вложений (раздел 3.2 ТЗ: image_picker + file_picker).
class AttachmentPicker {
  AttachmentPicker._();

  static const _uuid = Uuid();

  static Future<NoteAttachment?> pickImage({required bool camera}) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return null;
    return NoteAttachment(
      id: _uuid.v4(),
      type: AttachmentType.image,
      path: file.path,
      name: file.name,
      createdAt: DateTime.now(),
    );
  }

  static Future<NoteAttachment?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    return NoteAttachment(
      id: _uuid.v4(),
      type: AttachmentType.pdf,
      path: path,
      name: result!.files.single.name,
      createdAt: DateTime.now(),
    );
  }

  static Future<NoteAttachment?> pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null) return null;
    return NoteAttachment(
      id: _uuid.v4(),
      type: AttachmentType.audio,
      path: path,
      name: result!.files.single.name,
      createdAt: DateTime.now(),
    );
  }
}
