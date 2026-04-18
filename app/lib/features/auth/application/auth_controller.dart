import 'package:app/features/auth/application/auth_state.dart';
import 'package:app/features/auth/data/repositories/api_auth_repository.dart';
import 'package:app/features/devices/data/device_registration_service.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthStatus>(AuthController.new);

class AuthController extends AsyncNotifier<AuthStatus> {
  @override
  Future<AuthStatus> build() async {
    final authRepository = ref.read(authRepositoryProvider);
    final deviceRegistrationService = ref.read(
      deviceRegistrationServiceProvider,
    );
    final hasSession = await authRepository.hasActiveSession();

    if (hasSession) {
      try {
        await deviceRegistrationService.registerCurrentDevice();
      } catch (_) {
        // Device registration should not block session restoration.
      }
      return AuthStatus.authenticated;
    }

    return AuthStatus.unauthenticated;
  }

  Future<void> signIn({required String email, required String password}) async {
    final authRepository = ref.read(authRepositoryProvider);
    final deviceRegistrationService = ref.read(
      deviceRegistrationServiceProvider,
    );
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final isSignedIn = await authRepository.signIn(
        email: email,
        password: password,
      );
      if (isSignedIn) {
        try {
          await deviceRegistrationService.registerCurrentDevice();
        } catch (_) {
          // Device registration should not block authentication.
        }
        ref.invalidate(currentProfileProvider);
      }
      return isSignedIn ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    });
  }

  Future<void> signOut() async {
    final authRepository = ref.read(authRepositoryProvider);
    final deviceRegistrationService = ref.read(
      deviceRegistrationServiceProvider,
    );
    state = const AsyncValue.loading();
    try {
      try {
        await deviceRegistrationService.unregisterCurrentDevice();
      } catch (_) {
        // Sign-out should continue even if device cleanup fails.
      }
      await authRepository.signOut();
    } catch (_) {
      // Intentionally ignored: local sign-out state should always win.
    } finally {
      ref.invalidate(currentProfileProvider);
      state = const AsyncValue.data(AuthStatus.unauthenticated);
    }
  }

  Future<void> signUp({required String email, required String password}) async {
    final authRepository = ref.read(authRepositoryProvider);
    await authRepository.signUp(email: email, password: password);
  }

  Future<void> signUpAdmin({
    required String email,
    required String password,
  }) async {
    final authRepository = ref.read(authRepositoryProvider);
    await authRepository.signUpAdmin(email: email, password: password);
  }

  Future<void> requestPasswordReset({required String email}) async {
    final authRepository = ref.read(authRepositoryProvider);
    await authRepository.requestPasswordReset(email: email);
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
    required bool logoutOtherSessions,
  }) async {
    final authRepository = ref.read(authRepositoryProvider);
    await authRepository.resetPassword(
      token: token,
      newPassword: newPassword,
      logoutOtherSessions: logoutOtherSessions,
    );
  }

  Future<void> verifyEmail({
    required String token,
    String type = 'signup',
  }) async {
    final authRepository = ref.read(authRepositoryProvider);
    await authRepository.verifyEmail(token: token, type: type);
  }

  Future<void> resendEmailVerification({required String email}) async {
    final authRepository = ref.read(authRepositoryProvider);
    await authRepository.resendEmailVerification(email: email);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required bool logoutOtherSessions,
  }) async {
    final authRepository = ref.read(authRepositoryProvider);
    await authRepository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      logoutOtherSessions: logoutOtherSessions,
    );
  }

  Future<void> deleteAccount({required String currentPassword}) async {
    final authRepository = ref.read(authRepositoryProvider);
    final deviceRegistrationService = ref.read(
      deviceRegistrationServiceProvider,
    );
    try {
      await deviceRegistrationService.unregisterCurrentDevice();
    } catch (_) {
      // Account deletion should continue even if device cleanup fails.
    }
    await authRepository.deleteAccount(currentPassword: currentPassword);
    ref.invalidate(currentProfileProvider);
    state = const AsyncValue.data(AuthStatus.unauthenticated);
  }
}
