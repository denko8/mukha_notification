import '../../../core/services/json_store.dart';
import '../models/family_member.dart';

/// Локальная версия семейной доски.
///
/// В боевой версии члены семьи и инвайты живут в Firebase Realtime Database,
/// а приём приглашения происходит по динамической ссылке. Сейчас вход по
/// коду имитируется на устройстве, чтобы весь флоу можно было протестировать
/// без бэкенда.
class FamilyRepository {
  final JsonStoreBase store;
  static const _membersFile = 'family_members.json';
  static const _invitesFile = 'family_invites.json';
  static const _inviteBase = 'https://smartnotes.app/invite/';

  FamilyRepository(this.store);

  Future<List<FamilyMember>> loadMembers() async {
    final raw = await store.readList(_membersFile);
    if (raw.isEmpty) {
      final me = FamilyMember(
        id: 'me',
        name: 'Я',
        joinedAt: DateTime.now(),
        isMe: true,
      );
      await store.writeList(_membersFile, [me.toMap()]);
      return [me];
    }
    return raw.map(FamilyMember.fromMap).toList();
  }

  Future<FamilyInvite> createInvite(String token) async {
    final invites = await _loadInvites();
    final invite = FamilyInvite(
      token: token,
      link: '$_inviteBase$token',
      createdAt: DateTime.now(),
    );
    invites.add(invite);
    await store.writeList(
      _invitesFile,
      invites.map((e) => e.toMap()).toList(),
    );
    return invite;
  }

  /// Имитация принятия приглашения: добавляет участника по коду.
  Future<FamilyMember> acceptInvite(String token, String name) async {
    final invites = await _loadInvites();
    final matches = invites.where((i) => i.token == token).toList();
    if (matches.isEmpty) {
      throw StateError('Приглашение не найдено. Проверьте код.');
    }
    final members = await loadMembers();
    final member = FamilyMember(
      id: 'member_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      joinedAt: DateTime.now(),
    );
    members.add(member);
    await store.writeList(
      _membersFile,
      members.map((e) => e.toMap()).toList(),
    );
    return member;
  }

  Future<List<FamilyInvite>> _loadInvites() async {
    final raw = await store.readList(_invitesFile);
    return raw.map(FamilyInvite.fromMap).toList();
  }
}
