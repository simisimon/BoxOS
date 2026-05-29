import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/app_notification.dart';
import 'package:app/features/profile/domain/models/gym_membership.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_profile.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:app/features/profile/domain/repositories/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiProfileRepository(dio: dio, tokenStorage: tokenStorage);
});

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<UserProfile> fetchProfile() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/profile',
      options: Options(headers: await _authHeaders()),
    );
    return _profileFromJson(response.data);
  }

  @override
  Future<UserProfile> updateProfile({
    required String displayName,
    required String nickname,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/profile',
      data: {'display_name': displayName, 'nickname': nickname},
      options: Options(headers: await _authHeaders()),
    );
    return _profileFromJson(response.data);
  }

  @override
  Future<NotificationPreferences> fetchNotificationPreferences() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/profile/notifications',
      options: Options(headers: await _authHeaders()),
    );
    return _notificationPreferencesFromJson(response.data);
  }

  @override
  Future<NotificationPreferences> updateNotificationPreferences({
    required NotificationPreferences preferences,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/profile/notifications',
      data: {
        'booking_confirmations': preferences.bookingConfirmations,
        'waitlist_promotions': preferences.waitlistPromotions,
        'payment_issues': preferences.paymentIssues,
        'wod_posted': preferences.wodPosted,
        'pr_achievements': preferences.prAchievements,
        'announcement_activity': preferences.announcementActivity,
      },
      options: Options(headers: await _authHeaders()),
    );
    return _notificationPreferencesFromJson(response.data);
  }

  @override
  Future<NotificationInbox> fetchNotifications() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/notifications',
      options: Options(headers: await _authHeaders()),
    );
    return _notificationInboxFromJson(response.data);
  }

  @override
  Future<NotificationInbox> markAllNotificationsRead() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/notifications/read-all',
      data: const <String, dynamic>{},
      options: Options(headers: await _authHeaders()),
    );
    return _notificationInboxFromJson(response.data);
  }

  @override
  Future<List<RoleManagedUser>> fetchRoleManagedUsers() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/roles/users',
      options: Options(headers: await _authHeaders()),
    );
    final users = response.data?['users'] as List<dynamic>? ?? const [];
    return users
        .map((user) => _roleManagedUserFromJson(user as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<RoleManagedUser> updateUserRole({
    required int userId,
    required List<UserRole> roles,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/roles/users',
      data: {
        'user_id': userId,
        'roles': roles.map((role) => role.apiValue).toList(),
      },
      options: Options(headers: await _authHeaders()),
    );
    return _roleManagedUserFromJson(response.data);
  }

  @override
  Future<UserProfile> updateActiveRole({required UserRole role}) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/profile/active-role',
      data: {'role': role.apiValue},
      options: Options(headers: await _authHeaders()),
    );
    return _profileFromJson(response.data);
  }

  @override
  Future<UserProfile> updateActiveGym({required int gymId}) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/profile/active-gym',
      data: {'gym_id': gymId},
      options: Options(headers: await _authHeaders()),
    );
    return _profileFromJson(response.data);
  }

  Future<Map<String, String>> _authHeaders() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      throw Exception('No active session found.');
    }
    return {'Authorization': 'Bearer ${tokens.accessToken}'};
  }

  UserProfile _profileFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing profile data.');
    }
    return UserProfile(
      email: data['email'] as String? ?? '',
      accountType: accountTypeFromApi(
        data['account_type'] as String? ?? 'athlete',
      ),
      role: userRoleFromApi(data['role'] as String? ?? 'athlete'),
      availableRoles: _rolesFromJson(data['available_roles']),
      displayName: data['display_name'] as String? ?? '',
      nickname: data['nickname'] as String? ?? '',
      notificationPreferences: const NotificationPreferences(
        bookingConfirmations: true,
        waitlistPromotions: true,
        paymentIssues: true,
        wodPosted: true,
        prAchievements: true,
        announcementActivity: true,
      ),
      activeGym: _gymFromJson(data['active_gym'] as Map<String, dynamic>?),
      memberships: _membershipsFromJson(data['memberships']),
    );
  }

  NotificationPreferences _notificationPreferencesFromJson(
    Map<String, dynamic>? data,
  ) {
    if (data == null) {
      throw Exception('Missing notification preference data.');
    }
    return NotificationPreferences(
      bookingConfirmations: data['booking_confirmations'] as bool? ?? true,
      waitlistPromotions: data['waitlist_promotions'] as bool? ?? true,
      paymentIssues: data['payment_issues'] as bool? ?? true,
      wodPosted: data['wod_posted'] as bool? ?? true,
      prAchievements: data['pr_achievements'] as bool? ?? true,
      announcementActivity: data['announcement_activity'] as bool? ?? true,
    );
  }

  NotificationInbox _notificationInboxFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing notification inbox data.');
    }
    final items = data['notifications'] as List<dynamic>? ?? const [];
    return NotificationInbox(
      unreadCount: data['unread_count'] as int? ?? 0,
      notifications: items
          .map(
            (item) => _appNotificationFromJson(item as Map<String, dynamic>?),
          )
          .toList(),
    );
  }

  AppNotification _appNotificationFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing notification data.');
    }
    return AppNotification(
      id: data['id'] as int? ?? 0,
      type: data['type'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      entityType: data['entity_type'] as String?,
      entityId: data['entity_id'] as int?,
      readAt: data['read_at'] == null
          ? null
          : DateTime.parse(data['read_at'] as String),
      createdAt: DateTime.parse(data['created_at'] as String? ?? ''),
    );
  }

  RoleManagedUser _roleManagedUserFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing managed user data.');
    }
    return RoleManagedUser(
      id: data['id'] as int? ?? 0,
      membershipId: data['membership_id'] as int? ?? 0,
      email: data['email'] as String? ?? '',
      role: userRoleFromApi(data['role'] as String? ?? 'athlete'),
      availableRoles: _rolesFromJson(data['available_roles']),
      displayName: data['display_name'] as String? ?? '',
      nickname: data['nickname'] as String? ?? '',
      canEditRole: data['can_edit_role'] as bool? ?? false,
    );
  }

  List<UserRole> _rolesFromJson(dynamic data) {
    final rawRoles = data as List<dynamic>? ?? const ['athlete'];
    final roles = rawRoles
        .map((role) => userRoleFromApi(role as String? ?? 'athlete'))
        .toList();
    return roles.isEmpty ? const [UserRole.athlete] : roles;
  }

  GymSummary? _gymFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    return GymSummary(
      id: data['id'] as int? ?? 0,
      name: data['name'] as String? ?? '',
      slug: data['slug'] as String? ?? '',
      logoUrl: data['logo_url'] as String? ?? '',
      timezone: data['timezone'] as String? ?? '',
    );
  }

  List<GymMembership> _membershipsFromJson(dynamic data) {
    final rawMemberships = data as List<dynamic>? ?? const [];
    return rawMemberships.map((membership) {
      final item = membership as Map<String, dynamic>? ?? const {};
      return GymMembership(
        gym: GymSummary(
          id: item['gym_id'] as int? ?? 0,
          name: item['gym_name'] as String? ?? '',
          slug: item['gym_slug'] as String? ?? '',
          logoUrl: item['gym_logo_url'] as String? ?? '',
          timezone: item['gym_timezone'] as String? ?? '',
        ),
        role: userRoleFromApi(item['role'] as String? ?? 'athlete'),
        availableRoles: _rolesFromJson(item['available_roles']),
        status: item['status'] as String? ?? 'active',
      );
    }).toList();
  }
}
