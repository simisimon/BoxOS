/// What stands between the user and deleting their account: boxes they own
/// alone. A box with other members needs a new owner first; a box with no
/// other members is deleted together with the account.
class AccountDeletionCheck {
  const AccountDeletionCheck({
    this.gymsNeedingOwner = const [],
    this.emptyGyms = const [],
  });

  factory AccountDeletionCheck.fromJson(Map<String, dynamic> json) {
    final needingOwner = json['gyms_needing_owner'] as List<dynamic>? ?? [];
    final empty = json['empty_gyms'] as List<dynamic>? ?? [];
    return AccountDeletionCheck(
      gymsNeedingOwner: needingOwner
          .map((gym) => SoleOwnedGym.fromJson(gym as Map<String, dynamic>))
          .toList(),
      emptyGyms: empty
          .map((gym) => SoleOwnedGym.fromJson(gym as Map<String, dynamic>))
          .toList(),
    );
  }

  final List<SoleOwnedGym> gymsNeedingOwner;
  final List<SoleOwnedGym> emptyGyms;

  bool get canDelete => gymsNeedingOwner.isEmpty;
}

class SoleOwnedGym {
  const SoleOwnedGym({
    required this.id,
    required this.name,
    this.members = const [],
  });

  factory SoleOwnedGym.fromJson(Map<String, dynamic> json) {
    final members = json['members'] as List<dynamic>? ?? [];
    return SoleOwnedGym(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      members: members
          .map(
            (member) => OwnerCandidate.fromJson(member as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final int id;
  final String name;
  final List<OwnerCandidate> members;
}

class OwnerCandidate {
  const OwnerCandidate({
    required this.id,
    required this.email,
    this.displayName = '',
    this.role = 'athlete',
  });

  factory OwnerCandidate.fromJson(Map<String, dynamic> json) {
    return OwnerCandidate(
      id: json['id'] as int,
      email: json['email'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      role: json['role'] as String? ?? 'athlete',
    );
  }

  final int id;
  final String email;
  final String displayName;
  final String role;

  String get label => displayName.trim().isEmpty ? email : displayName.trim();
}
