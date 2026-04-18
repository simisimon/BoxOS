import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/auth/domain/models/auth_tokens.dart';
import 'package:app/features/auth/domain/repositories/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiAuthRepository(dio: dio, tokenStorage: tokenStorage);
});

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<bool> hasActiveSession() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      return false;
    }

    try {
      await _dio.get<void>(
        '/auth/session',
        options: Options(headers: _authHeaders(tokens.accessToken)),
      );
      return true;
    } on DioException catch (error) {
      final isUnauthorized = error.response?.statusCode == 401;
      if (!isUnauthorized) {
        rethrow;
      }
    }

    return _refreshSession();
  }

  @override
  Future<bool> signIn({required String email, required String password}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    await _writeTokensFromResponse(response.data);
    return true;
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    await _dio.post<void>(
      '/auth/signup',
      data: {'email': email, 'password': password},
    );
  }

  @override
  Future<void> signUpAdmin({
    required String email,
    required String password,
  }) async {
    await _dio.post<void>(
      '/auth/signup-admin',
      data: {'email': email, 'password': password},
    );
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    await _dio.post<void>(
      '/auth/request-password-reset',
      data: {'email': email},
    );
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
    required bool logoutOtherSessions,
  }) async {
    await _dio.post<void>(
      '/auth/reset-password',
      data: {
        'token': token,
        'new_password': newPassword,
        'logout_other_sessions': logoutOtherSessions,
      },
    );
    await _tokenStorage.clearTokens();
  }

  @override
  Future<void> verifyEmail({
    required String token,
    String type = 'signup',
  }) async {
    await _dio.post<void>(
      '/auth/verify-email',
      data: {'token': token, 'type': type},
    );
  }

  @override
  Future<void> resendEmailVerification({required String email}) async {
    await _dio.post<void>('/auth/resend-verification', data: {'email': email});
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required bool logoutOtherSessions,
  }) async {
    final tokens = await _requireTokens();
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/change-password',
      data: {
        'current_password': currentPassword,
        'new_password': newPassword,
        'logout_other_sessions': logoutOtherSessions,
      },
      options: Options(headers: _authHeaders(tokens.accessToken)),
    );
    await _writeTokensFromResponse(response.data);
  }

  @override
  Future<void> deleteAccount({required String currentPassword}) async {
    final tokens = await _requireTokens();
    await _dio.delete<void>(
      '/auth/account',
      data: {'current_password': currentPassword},
      options: Options(headers: _authHeaders(tokens.accessToken)),
    );
    await _tokenStorage.clearTokens();
  }

  @override
  Future<void> signOut() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens != null) {
      try {
        await _dio.post<void>(
          '/auth/logout',
          options: Options(headers: _authHeaders(tokens.accessToken)),
        );
      } on DioException {
        // Local sign-out still wins if the backend session is already gone.
      }
    }
    await _tokenStorage.clearTokens();
  }

  Future<bool> _refreshSession() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      return false;
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': tokens.refreshToken},
      );
      await _writeTokensFromResponse(response.data);
      return true;
    } on DioException {
      await _tokenStorage.clearTokens();
      return false;
    }
  }

  Future<AuthTokens> _requireTokens() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      throw Exception('No active session found.');
    }
    return tokens;
  }

  Future<void> _writeTokensFromResponse(Map<String, dynamic>? data) async {
    final accessToken = data?['access_token'] as String?;
    final refreshToken = data?['refresh_token'] as String?;

    if (accessToken == null || refreshToken == null) {
      throw Exception('Missing session tokens in backend response.');
    }

    await _tokenStorage.writeTokens(
      AuthTokens(accessToken: accessToken, refreshToken: refreshToken),
    );
  }

  Map<String, String> _authHeaders(String accessToken) {
    return {'Authorization': 'Bearer $accessToken'};
  }
}
