import 'package:app/features/profile/domain/models/app_notification.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:app/features/profile/domain/models/user_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final currentProfileProvider = FutureProvider<UserProfile>((ref) async {
  final repository = ref.read(profileRepositoryProvider);
  return repository.fetchProfile();
});

final notificationPreferencesProvider = FutureProvider<NotificationPreferences>(
  (ref) async {
    final repository = ref.read(profileRepositoryProvider);
    return repository.fetchNotificationPreferences();
  },
);

final notificationInboxProvider = FutureProvider<NotificationInbox>((ref) async {
  final repository = ref.read(profileRepositoryProvider);
  return repository.fetchNotifications();
});
