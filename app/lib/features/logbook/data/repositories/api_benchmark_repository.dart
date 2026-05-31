import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/logbook/domain/models/benchmark_workout.dart';
import 'package:app/features/logbook/domain/repositories/benchmark_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final benchmarkRepositoryProvider = Provider<BenchmarkRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiBenchmarkRepository(dio: dio, tokenStorage: tokenStorage);
});

class ApiBenchmarkRepository implements BenchmarkRepository {
  ApiBenchmarkRepository({
    required Dio dio,
    required TokenStorage tokenStorage,
  }) : _dio = dio,
       _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<List<BenchmarkWorkout>> fetchBenchmarks() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/benchmark-workouts',
      options: Options(headers: await _authHeaders()),
    );
    final items = response.data?['workouts'] as List<dynamic>? ?? const [];
    return items
        .map(
          (item) => BenchmarkWorkout.fromJson(item as Map<String, dynamic>),
        )
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
