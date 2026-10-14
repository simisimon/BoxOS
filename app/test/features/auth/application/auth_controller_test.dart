import 'dart:async';
import 'dart:typed_data';

import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/application/auth_state.dart';
import 'package:app/features/auth/data/repositories/api_auth_repository.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/auth/domain/repositories/auth_repository.dart';
import 'package:app/features/auth/domain/models/auth_tokens.dart';
import 'package:app/features/devices/data/device_registration_service.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/app_notification.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_profile.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:app/features/profile/domain/repositories/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthRepository implements AuthRepository {
  bool _hasSession;
  Completer<bool>? _signInCompleter;
  bool throwOnSignOut;
  String? lastSignUpEmail;
  String? lastResetEmail;
  String? lastResetToken;
  String? lastResetPassword;
  bool? lastResetLogoutOtherSessions;
  String? lastVerifyToken;
  String? lastVerifyType;
  String? lastResendEmail;
  String? lastChangeCurrentPassword;
  String? lastChangeNewPassword;
  bool? lastChangeLogoutOtherSessions;
  String? lastDeleteCurrentPassword;

  FakeAuthRepository({bool hasSession = false, this.throwOnSignOut = false})
    : _hasSession = hasSession;

  @override
  Future<bool> hasActiveSession() async {
    return _hasSession;
  }

  @override
  Future<bool> signIn({required String email, required String password}) async {
    _signInCompleter = Completer<bool>();
    final result = await _signInCompleter!.future;
    _hasSession = result;
    return result;
  }

  void completeSignIn(bool result) {
    _signInCompleter?.complete(result);
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    lastSignUpEmail = email;
  }

  @override
  Future<void> signUpAdmin({
    required String email,
    required String password,
  }) async {
    lastSignUpEmail = email;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    lastResetEmail = email;
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
    required bool logoutOtherSessions,
  }) async {
    lastResetToken = token;
    lastResetPassword = newPassword;
    lastResetLogoutOtherSessions = logoutOtherSessions;
  }

  @override
  Future<void> verifyEmail({
    required String token,
    String type = 'signup',
  }) async {
    lastVerifyToken = token;
    lastVerifyType = type;
  }

  @override
  Future<void> resendEmailVerification({required String email}) async {
    lastResendEmail = email;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required bool logoutOtherSessions,
  }) async {
    lastChangeCurrentPassword = currentPassword;
    lastChangeNewPassword = newPassword;
    lastChangeLogoutOtherSessions = logoutOtherSessions;
  }

  @override
  Future<void> deleteAccount({required String currentPassword}) async {
    lastDeleteCurrentPassword = currentPassword;
    _hasSession = false;
  }

  @override
  Future<void> signOut() async {
    if (throwOnSignOut) {
      throw Exception('Sign out failed');
    }
    _hasSession = false;
  }
}

class FakeDeviceRegistrationService extends DeviceRegistrationService {
  FakeDeviceRegistrationService()
    : super(
        dio: Dio(),
        tokenStorage: _FakeTokenStorage(),
        secureStorage: const FlutterSecureStorage(),
      );

  int registerCalls = 0;
  int unregisterCalls = 0;

  @override
  Future<void> registerCurrentDevice() async {
    registerCalls += 1;
  }

  @override
  Future<void> unregisterCurrentDevice() async {
    unregisterCalls += 1;
  }
}

class _FakeTokenStorage implements TokenStorage {
  @override
  Future<void> clearTokens() async {}

  @override
  Future<AuthTokens?> readTokens() async => null;

  @override
  Future<void> writeTokens(AuthTokens tokens) async {}
}

class FakeProfileRepository implements ProfileRepository {
  int fetchProfileCalls = 0;

  @override
  Future<UserProfile> fetchProfile() async {
    fetchProfileCalls += 1;
    return const UserProfile(
      email: 'demo@boxos.app',
      accountType: AccountType.athlete,
      role: UserRole.athlete,
      availableRoles: [UserRole.athlete],
      displayName: 'Demo Athlete',
      nickname: 'demo',
      notificationPreferences: NotificationPreferences(
        bookingConfirmations: true,
        waitlistPromotions: true,
        paymentIssues: true,
        wodPosted: true,
        prAchievements: true,
        announcementActivity: true,
      ),
      activeGym: null,
      memberships: [],
    );
  }

  @override
  Future<UserProfile> updateProfile({
    required String displayName,
    required String nickname,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> uploadProfileAvatar({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> deleteProfileAvatar() {
    throw UnimplementedError();
  }

  @override
  Future<NotificationPreferences> fetchNotificationPreferences() {
    throw UnimplementedError();
  }

  @override
  Future<NotificationPreferences> updateNotificationPreferences({
    required NotificationPreferences preferences,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<NotificationInbox> fetchNotifications() async {
    return const NotificationInbox(unreadCount: 0, notifications: []);
  }

  @override
  Future<NotificationInbox> markAllNotificationsRead() async {
    return const NotificationInbox(unreadCount: 0, notifications: []);
  }

  @override
  Future<List<RoleManagedUser>> fetchRoleManagedUsers() {
    throw UnimplementedError();
  }

  @override
  Future<RoleManagedUser> updateUserRole({
    required int userId,
    required List<UserRole> roles,
    UserRole? activeRole,
    MembershipStatus? status,
    String? adminNote,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> updateActiveRole({required UserRole role}) {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> updateActiveGym({required int gymId}) {
    throw UnimplementedError();
  }
}

void main() {
  test(
    'AuthController transitions through loading and authenticated',
    () async {
      final fakeRepository = FakeAuthRepository();
      final fakeDeviceService = FakeDeviceRegistrationService();
      final fakeProfileRepository = FakeProfileRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((ref) => fakeRepository),
          deviceRegistrationServiceProvider.overrideWith(
            (ref) => fakeDeviceService,
          ),
          profileRepositoryProvider.overrideWith(
            (ref) => fakeProfileRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authControllerProvider.future);
      expect(
        container.read(authControllerProvider).value,
        AuthStatus.unauthenticated,
      );
      await container.read(currentProfileProvider.future);
      expect(fakeProfileRepository.fetchProfileCalls, 1);

      final signInFuture = container
          .read(authControllerProvider.notifier)
          .signIn(email: 'demo@boxos.app', password: 'demopw');

      expect(container.read(authControllerProvider).isLoading, isTrue);

      fakeRepository.completeSignIn(true);
      await signInFuture;

      expect(
        container.read(authControllerProvider).value,
        AuthStatus.authenticated,
      );
      expect(fakeDeviceService.registerCalls, 1);
      await container.read(currentProfileProvider.future);
      expect(fakeProfileRepository.fetchProfileCalls, 2);
    },
  );

  test('AuthController signOut sets unauthenticated', () async {
    final fakeRepository = FakeAuthRepository(hasSession: true);
    final fakeDeviceService = FakeDeviceRegistrationService();
    final fakeProfileRepository = FakeProfileRepository();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => fakeRepository),
        deviceRegistrationServiceProvider.overrideWith(
          (ref) => fakeDeviceService,
        ),
        profileRepositoryProvider.overrideWith((ref) => fakeProfileRepository),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    expect(
      container.read(authControllerProvider).value,
      AuthStatus.authenticated,
    );
    await container.read(currentProfileProvider.future);
    expect(fakeProfileRepository.fetchProfileCalls, 1);

    await container.read(authControllerProvider.notifier).signOut();

    expect(
      container.read(authControllerProvider).value,
      AuthStatus.unauthenticated,
    );
    expect(fakeDeviceService.unregisterCalls, 1);
    await container.read(currentProfileProvider.future);
    expect(fakeProfileRepository.fetchProfileCalls, 2);
  });

  test(
    'AuthController signOut still sets unauthenticated on failure',
    () async {
      final fakeRepository = FakeAuthRepository(
        hasSession: true,
        throwOnSignOut: true,
      );
      final fakeDeviceService = FakeDeviceRegistrationService();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWith((ref) => fakeRepository),
          deviceRegistrationServiceProvider.overrideWith(
            (ref) => fakeDeviceService,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(authControllerProvider.future);
      expect(
        container.read(authControllerProvider).value,
        AuthStatus.authenticated,
      );

      await container.read(authControllerProvider.notifier).signOut();

      expect(
        container.read(authControllerProvider).value,
        AuthStatus.unauthenticated,
      );
      expect(fakeDeviceService.unregisterCalls, 1);
    },
  );

  test('AuthController signUp delegates to repository', () async {
    final fakeRepository = FakeAuthRepository();
    final fakeDeviceService = FakeDeviceRegistrationService();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => fakeRepository),
        deviceRegistrationServiceProvider.overrideWith(
          (ref) => fakeDeviceService,
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(authControllerProvider.notifier)
        .signUp(email: 'new@boxos.app', password: 'secret123');

    expect(fakeRepository.lastSignUpEmail, 'new@boxos.app');
    expect(fakeDeviceService.registerCalls, 0);
  });

  test('AuthController forgot/reset/verify delegates to repository', () async {
    final fakeRepository = FakeAuthRepository();
    final fakeDeviceService = FakeDeviceRegistrationService();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => fakeRepository),
        deviceRegistrationServiceProvider.overrideWith(
          (ref) => fakeDeviceService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(authControllerProvider.notifier);
    await notifier.requestPasswordReset(email: 'athlete@boxos.app');
    await notifier.resetPassword(
      token: 'reset-token',
      newPassword: 'new-pass',
      logoutOtherSessions: true,
    );
    await notifier.verifyEmail(token: 'verify-token');
    await notifier.verifyEmail(token: 'verify-token-email', type: 'email');
    await notifier.resendEmailVerification(email: 'athlete@boxos.app');

    expect(fakeRepository.lastResetEmail, 'athlete@boxos.app');
    expect(fakeRepository.lastResetToken, 'reset-token');
    expect(fakeRepository.lastResetPassword, 'new-pass');
    expect(fakeRepository.lastResetLogoutOtherSessions, isTrue);
    expect(fakeRepository.lastVerifyToken, 'verify-token-email');
    expect(fakeRepository.lastVerifyType, 'email');
    expect(fakeRepository.lastResendEmail, 'athlete@boxos.app');
  });

  test('AuthController changePassword delegates to repository', () async {
    final fakeRepository = FakeAuthRepository();
    final fakeDeviceService = FakeDeviceRegistrationService();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => fakeRepository),
        deviceRegistrationServiceProvider.overrideWith(
          (ref) => fakeDeviceService,
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(authControllerProvider.notifier)
        .changePassword(
          currentPassword: 'old-pass',
          newPassword: 'new-pass',
          logoutOtherSessions: true,
        );

    expect(fakeRepository.lastChangeCurrentPassword, 'old-pass');
    expect(fakeRepository.lastChangeNewPassword, 'new-pass');
    expect(fakeRepository.lastChangeLogoutOtherSessions, isTrue);
  });

  test('AuthController deleteAccount signs user out locally', () async {
    final fakeRepository = FakeAuthRepository(hasSession: true);
    final fakeDeviceService = FakeDeviceRegistrationService();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWith((ref) => fakeRepository),
        deviceRegistrationServiceProvider.overrideWith(
          (ref) => fakeDeviceService,
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    await container
        .read(authControllerProvider.notifier)
        .deleteAccount(currentPassword: 'current-pass');

    expect(fakeRepository.lastDeleteCurrentPassword, 'current-pass');
    expect(
      container.read(authControllerProvider).value,
      AuthStatus.unauthenticated,
    );
    expect(fakeDeviceService.unregisterCalls, 1);
  });
}
