import 'package:share_plus/share_plus.dart';

import '../../features/notes/models/note.dart';
import '../utils/date_formatter.dart';

/// Отправка заметки через системный лист «Поделиться».
///
/// Единая точка для всех экранов: пользователь сам выбирает приложение
/// (Telegram, MAX, VK, WhatsApp, почта, SMS…), приложению не нужны
/// ни API-ключи, ни OAuth. На Android системный лист запоминает частые
/// цели и показывает их первыми — фактически шеринг в один тап.
class ShareService {
  /// Собирает текст заметки для стороннего приложения.
  String formatNote(AppNote note) {
    final buffer = StringBuffer(note.text.trim());
    if (note.reminderAt != null) {
      buffer.write('\nНапоминание: ${DateFormatter.full(note.reminderAt!)}');
    }
    if (note.isFamily) {
      buffer.write('\nСемейная заметка');
    }
    return buffer.toString();
  }

  /// Открывает системный лист sharing. [subject] используется почтой
  /// и частью мессенджеров как тема сообщения.
  Future<void> shareNote(AppNote note) {
    return Share.share(
      formatNote(note),
      subject: 'Заметка из Smart Notes',
    );
  }
}
