import 'package:app/features/auth/domain/models/auth_tokens.dart';

abstract class TokenStorage {
  Future<AuthTokens?> readTokens();

  Future<void> writeTokens(AuthTokens tokens);

  Future<void> clearTokens();
}
