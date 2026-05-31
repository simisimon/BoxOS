import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/logbook/domain/models/exercise.dart';
import 'package:app/features/logbook/domain/repositories/exercise_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiExerciseRepository(dio: dio, tokenStorage: tokenStorage);
});

class ApiExerciseRepository implements ExerciseRepository {
  ApiExerciseRepository({
    required Dio dio,
    required TokenStorage tokenStorage,
  }) : _dio = dio,
       _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<List<Exercise>> fetchExercises({String query = '', int limit = 50}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/exercises',
      queryParameters: {'query': query, 'limit': limit},
      options: Options(headers: await _authHeaders()),
    );
    final items = response.data?['exercises'] as List<dynamic>? ?? const [];
    return items
        .map((item) => Exercise.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, String>> _authHeaders() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      throw Exception('No active session found.');
    }
    return {'Authorization': 'Bearer ${tokens.accessToken}'};
  }
}
