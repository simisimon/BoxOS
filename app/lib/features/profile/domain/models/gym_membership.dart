import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/domain/models/user_role.dart';

class GymMembership {
  const GymMembership({
    required this.gym,
    required this.role,
    required this.availableRoles,
    required this.status,
  });

  final GymSummary gym;
  final UserRole role;
  final List<UserRole> availableRoles;
  final String status;
}
