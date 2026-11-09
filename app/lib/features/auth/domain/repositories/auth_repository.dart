import 'package:app/features/auth/domain/models/account_deletion_check.dart';

abstract class AuthRepository {
  Future<bool> hasActiveSession();

  Future<bool> signIn({required String email, required String password});

  Future<void> signUp({required String email, required String password});

  Future<void> signUpAdmin({required String email, required String password});

  Future<void> requestPasswordReset({required String email});

  Future<void> resetPassword({
    required String token,
    required String newPassword,
    required bool logoutOtherSessions,
  });

  Future<void> verifyEmail({required String token, String type = 'signup'});

  Future<void> resendEmailVerification({required String email});

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required bool logoutOtherSessions,
  });

  Future<AccountDeletionCheck> fetchAccountDeletionCheck();

  /// Makes [userId], an existing member of [gymId], an owner of that box.
  Future<void> addGymOwner({required int gymId, required int userId});

  /// [deleteEmptyGyms] confirms deleting boxes the user owns alone that have
  /// no other members.
  Future<void> deleteAccount({
    required String currentPassword,
    bool deleteEmptyGyms = false,
  });

  Future<void> signOut();
}
