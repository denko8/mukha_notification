/// Тип прикреплённого файла.
enum AttachmentType { image, pdf, audio, other }

class NoteAttachment {
  final String id;
  final AttachmentType type;

  /// Локальный путь файла на устройстве.
  /// После подключения Firebase Storage здесь будет URL (миграция в репозитории).
  final String path;
  final String name;
  final DateTime createdAt;

  const NoteAttachment({
    required this.id,
    required this.type,
    required this.path,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'path': path,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory NoteAttachment.fromMap(Map<String, dynamic> map) => NoteAttachment(
        id: map['id'] as String,
        type: AttachmentType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => AttachmentType.other,
        ),
        path: map['path'] as String,
        name: map['name'] as String? ?? 'Файл',
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
