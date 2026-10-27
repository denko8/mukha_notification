class FamilyMember {
  final String id;
  final String name;
  final bool isMe;
  final DateTime joinedAt;

  const FamilyMember({
    required this.id,
    required this.name,
    required this.joinedAt,
    this.isMe = false,
  });

  /// Инициал для аватара-кружка (раздел 2.2 ТЗ).
  String get initial => name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'isMe': isMe,
        'joinedAt': joinedAt.toIso8601String(),
      };

  factory FamilyMember.fromMap(Map<String, dynamic> map) => FamilyMember(
        id: map['id'] as String,
        name: map['name'] as String? ?? 'Гость',
        isMe: map['isMe'] as bool? ?? false,
        joinedAt: DateTime.parse(map['joinedAt'] as String),
      );
}

/// Приглашение в семью: токен и ссылка-инвайт (раздел 2.2 ТЗ).
class FamilyInvite {
  final String token;
  final String link;
  final DateTime createdAt;

  const FamilyInvite({
    required this.token,
    required this.link,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'token': token,
        'link': link,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FamilyInvite.fromMap(Map<String, dynamic> map) => FamilyInvite(
        token: map['token'] as String,
        link: map['link'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}
