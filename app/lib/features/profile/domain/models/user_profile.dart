import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/gym_membership.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:app/features/profile/domain/models/user_role.dart';

class UserProfile {
  const UserProfile({
    required this.email,
    required this.accountType,
    required this.role,
    required this.availableRoles,
    required this.displayName,
    required this.nickname,
    required this.notificationPreferences,
    required this.activeGym,
    required this.memberships,
  });

  final String email;
  final AccountType accountType;
  final UserRole role;
  final List<UserRole> availableRoles;
  final String displayName;
  final String nickname;
  final NotificationPreferences notificationPreferences;
  final GymSummary? activeGym;
  final List<GymMembership> memberships;
}
