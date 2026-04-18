import 'package:app/features/profile/domain/models/user_role.dart';

class RoleManagedUser {
  const RoleManagedUser({
    required this.id,
    required this.membershipId,
    required this.email,
    required this.role,
    required this.availableRoles,
    required this.displayName,
    required this.nickname,
    required this.canEditRole,
  });

  final int id;
  final int membershipId;
  final String email;
  final UserRole role;
  final List<UserRole> availableRoles;
  final String displayName;
  final String nickname;
  final bool canEditRole;
}
