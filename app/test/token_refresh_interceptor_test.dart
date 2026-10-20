import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/auth/data/session/token_refresh_interceptor.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/auth/domain/models/auth_tokens.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryTokenStorage implements TokenStorage {
  AuthTokens? tokens = const AuthTokens(
    accessToken: 'old-access',
    refreshToken: 'old-refresh',
  );

  @override
  Future<AuthTokens?> readTokens() async => tokens;

  @override
  Future<void> writeTokens(AuthTokens value) async => tokens = value;

  @override
  Future<void> clearTokens() async => tokens = null;
}

/// Fake backend: only 'new-access' is valid; refresh works when [refreshOk].
class _FakeBackend implements HttpClientAdapter {
  _FakeBackend({this.refreshOk = true});

  final bool refreshOk;
  final List<String> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options.path);
    if (options.path == '/auth/refresh') {
      return refreshOk
          ? _json(200, {
              'access_token': 'new-access',
              'refresh_token': 'new-refresh',
            })
          : _json(401, {'detail': 'Session refresh failed.'});
    }
    return options.headers['Authorization'] == 'Bearer new-access'
        ? _json(200, {'ok': true})
        : _json(401, {'detail': 'Session expired.'});
  }

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

Dio _dio(_FakeBackend backend, _MemoryTokenStorage storage) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = backend;
  dio.interceptors.add(
    TokenRefreshInterceptor(dio: dio, tokenStorage: storage),
  );
  return dio;
}

Options _auth(String token) =>
    Options(headers: {'Authorization': 'Bearer $token'});

void main() {
  test('expired access token is refreshed once and requests retried', () async {
    final backend = _FakeBackend();
    final storage = _MemoryTokenStorage();
    final dio = _dio(backend, storage);

    final responses = await Future.wait([
      dio.patch<dynamic>('/profile/active-role', options: _auth('old-access')),
      dio.get<dynamic>('/roles/users', options: _auth('old-access')),
    ]);

    expect(responses.map((r) => r.statusCode), [200, 200]);
    expect(backend.calls.where((c) => c == '/auth/refresh'), hasLength(1));
    expect(storage.tokens?.refreshToken, 'new-refresh');
  });

  test('failed refresh surfaces the 401 and clears the tokens', () async {
    final backend = _FakeBackend(refreshOk: false);
    final storage = _MemoryTokenStorage();
    final dio = _dio(backend, storage);

    await expectLater(
      dio.get<dynamic>('/profile', options: _auth('old-access')),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          401,
        ),
      ),
    );
    expect(storage.tokens, isNull);
  });
}
