import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/auth/domain/models/auth_tokens.dart';
import 'package:dio/dio.dart';

/// Access tokens live 15 minutes. When an authorized request comes back 401,
/// this renews the session with the refresh token and retries the request
/// once. Requests failing at the same time share one refresh.
class TokenRefreshInterceptor extends Interceptor {
  TokenRefreshInterceptor({
    required Dio dio,
    required TokenStorage tokenStorage,
  }) : _dio = dio,
       _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;
  Future<AuthTokens?>? _refreshing;

  static const _retriedKey = 'authRetried';

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    final usedHeader = request.headers['Authorization'];
    // /auth/* calls handle their own 401s (login, session check, refresh).
    if (err.response?.statusCode != 401 ||
        usedHeader == null ||
        request.path.startsWith('/auth/') ||
        request.extra[_retriedKey] == true) {
      return handler.next(err);
    }

    final tokens = await _freshTokens(usedHeader as String);
    if (tokens == null) {
      return handler.next(err);
    }
    request.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    request.extra[_retriedKey] = true;
    try {
      handler.resolve(await _dio.fetch<dynamic>(request));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<AuthTokens?> _freshTokens(String usedHeader) async {
    final stored = await _tokenStorage.readTokens();
    if (stored == null) {
      return null;
    }
    // Another request already refreshed while this one was in flight.
    if (usedHeader != 'Bearer ${stored.accessToken}') {
      return stored;
    }
    return _refreshing ??= _refresh(
      stored,
    ).whenComplete(() => _refreshing = null);
  }

  Future<AuthTokens?> _refresh(AuthTokens stored) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': stored.refreshToken},
      );
      final accessToken = response.data?['access_token'] as String?;
      final refreshToken = response.data?['refresh_token'] as String?;
      if (accessToken == null || refreshToken == null) {
        return null;
      }
      final tokens = AuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      await _tokenStorage.writeTokens(tokens);
      return tokens;
    } on DioException {
      // Refresh token expired or revoked: same as ApiAuthRepository, the
      // next app start lands on the login screen.
      await _tokenStorage.clearTokens();
      return null;
    }
  }
}
