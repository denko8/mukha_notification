import 'note_attachment.dart';
import 'note_category.dart';

/// Заметка. `isFamily = true` — общая семейная (раздел 2.2 ТЗ),
/// `pendingSync = true` — создана/изменена офлайн и ждёт облачной синхронизации.
class AppNote {
  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? reminderAt;
  final bool isFamily;
  final String authorId;
  final String authorName;
  final bool done;
  final bool pendingSync;
  final List<NoteAttachment> attachments;
  final NoteCategory category;

  const AppNote({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    required this.authorId,
    this.reminderAt,
    this.isFamily = false,
    this.authorName = 'Я',
    this.done = false,
    this.pendingSync = true,
    this.attachments = const [],
    this.category = NoteCategory.general,
  });

  bool get hasReminder => reminderAt != null;

  AppNote copyWith({
    String? text,
    DateTime? updatedAt,
    DateTime? reminderAt,
    bool? isFamily,
    String? authorName,
    bool? done,
    bool? pendingSync,
    List<NoteAttachment>? attachments,
    NoteCategory? category,
    bool clearReminder = false,
  }) {
    return AppNote(
      id: id,
      text: text ?? this.text,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
      isFamily: isFamily ?? this.isFamily,
      authorId: authorId,
      authorName: authorName ?? this.authorName,
      done: done ?? this.done,
      pendingSync: pendingSync ?? this.pendingSync,
      attachments: attachments ?? this.attachments,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'reminderAt': reminderAt?.toIso8601String(),
        'isFamily': isFamily,
        'authorId': authorId,
        'authorName': authorName,
        'done': done,
        'pendingSync': pendingSync,
        'attachments': attachments.map((a) => a.toMap()).toList(),
        'category': category.name,
      };

  factory AppNote.fromMap(Map<String, dynamic> map) => AppNote(
        id: map['id'] as String,
        text: map['text'] as String? ?? '',
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
        reminderAt: map['reminderAt'] != null
            ? DateTime.parse(map['reminderAt'] as String)
            : null,
        isFamily: map['isFamily'] as bool? ?? false,
        authorId: map['authorId'] as String? ?? 'local',
        authorName: map['authorName'] as String? ?? 'Я',
        done: map['done'] as bool? ?? false,
        pendingSync: map['pendingSync'] as bool? ?? true,
        attachments: (map['attachments'] as List<dynamic>? ?? [])
            .map((e) => NoteAttachment.fromMap(e as Map<String, dynamic>))
            .toList(),
        category: NoteCategory.values.firstWhere(
          (c) => c.name == map['category'],
          orElse: () => NoteCategory.general,
        ),
      );
}
