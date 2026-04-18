import 'package:app/features/profile/domain/models/user_profile.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_role.dart';

abstract class ProfileRepository {
  Future<UserProfile> fetchProfile();

  Future<UserProfile> updateProfile({
    required String displayName,
    required String nickname,
  });

  Future<NotificationPreferences> fetchNotificationPreferences();

  Future<NotificationPreferences> updateNotificationPreferences({
    required NotificationPreferences preferences,
  });

  Future<List<RoleManagedUser>> fetchRoleManagedUsers();

  Future<RoleManagedUser> updateUserRole({
    required int userId,
    required List<UserRole> roles,
  });

  Future<UserProfile> updateActiveRole({required UserRole role});

  Future<UserProfile> updateActiveGym({required int gymId});
}
