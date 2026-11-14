import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final programmingLookupProvider = Provider<ProgrammingLookup>((ref) {
  return ProgrammingLookup(
    dio: ref.read(dioProvider),
    tokenStorage: ref.read(tokenStorageProvider),
  );
});

/// Suggestions for the block editor: the gym's movements (`/movements`) and
/// named workouts (`/workout-names`, benchmarks plus names used before).
class ProgrammingLookup {
  ProgrammingLookup({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  Future<List<String>> movementNames(String query, {int limit = 8}) async {
    final data = await _get('/movements', query, limit);
    return [
      for (final item in data['movements'] as List? ?? const [])
        (item as Map<String, dynamic>)['name'] as String,
    ];
  }

  Future<List<String>> workoutNames(String query, {int limit = 8}) async {
    final data = await _get('/workout-names', query, limit);
    return [
      for (final name in data['workout_names'] as List? ?? const [])
        name as String,
    ];
  }

  Future<Map<String, dynamic>> _get(
    String path,
    String query,
    int limit,
  ) async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) throw Exception('No active session found.');
    final response = await _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: {'query': query, 'limit': limit},
      options: Options(
        headers: {'Authorization': 'Bearer ${tokens.accessToken}'},
      ),
    );
    return response.data ?? const {};
  }
}
