import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../models/family_member.dart';

/// Тонкая обёртка-модель для UI: храним [FamilyMember] без доп. полей.
typedef FamilyMemberState = FamilyMember;

/// Имя выбрано отличным от `FamilyNotifier` из самого пакета riverpod 2.6+,
/// иначе возникает ambiguous_import.
class FamilyBoardNotifier extends AsyncNotifier<List<FamilyMember>> {
  @override
  Future<List<FamilyMember>> build() {
    return ref.read(familyRepositoryProvider).loadMembers();
  }

  Future<FamilyInvite> createInvite() {
    final token = ref.read(uuidProvider).v4().substring(0, 8);
    return ref.read(familyRepositoryProvider).createInvite(token);
  }

  Future<void> acceptInvite(String token, String name) async {
    await ref.read(familyRepositoryProvider).acceptInvite(token, name);
    state = AsyncData(await ref.read(familyRepositoryProvider).loadMembers());
  }
}
