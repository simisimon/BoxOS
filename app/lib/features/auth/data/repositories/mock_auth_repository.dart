import 'package:app/features/auth/domain/repositories/auth_repository.dart';

class MockAuthRepository implements AuthRepository {
  bool _isSignedIn = false;

  @override
  Future<bool> hasActiveSession() async {
    return _isSignedIn;
  }

  @override
  Future<bool> signIn({required String email, required String password}) async {
    final isValid = email.trim().isNotEmpty && password.trim().isNotEmpty;
    _isSignedIn = isValid;
    return _isSignedIn;
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpAdmin({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> requestPasswordReset({required String email}) async {}

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
    required bool logoutOtherSessions,
  }) async {}

  @override
  Future<void> verifyEmail({
    required String token,
    String type = 'signup',
  }) async {}

  @override
  Future<void> resendEmailVerification({required String email}) async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required bool logoutOtherSessions,
  }) async {}

  @override
  Future<void> deleteAccount({required String currentPassword}) async {}

  @override
  Future<void> signOut() async {
    _isSignedIn = false;
  }
}
