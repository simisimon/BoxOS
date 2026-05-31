import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/logbook/domain/models/personal_workout.dart';
import 'package:app/features/logbook/domain/repositories/personal_workout_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final personalWorkoutRepositoryProvider = Provider<PersonalWorkoutRepository>((
  ref,
) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiPersonalWorkoutRepository(dio: dio, tokenStorage: tokenStorage);
});

class ApiPersonalWorkoutRepository implements PersonalWorkoutRepository {
  ApiPersonalWorkoutRepository({
    required Dio dio,
    required TokenStorage tokenStorage,
  }) : _dio = dio,
       _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<List<PersonalWorkout>> fetchWorkouts() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/personal-workouts',
      options: Options(headers: await _authHeaders()),
    );
    final items = response.data?['workouts'] as List<dynamic>? ?? const [];
    return items
        .map(
          (item) => PersonalWorkout.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<PersonalWorkout> createWorkout({
    required String title,
    required WorkoutType type,
    required Map<String, dynamic> structure,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/personal-workouts',
      data: {
        'title': title,
        'type': type.apiValue,
        'structure': structure,
      },
      options: Options(headers: await _authHeaders()),
    );
    final workout = response.data?['workout'] as Map<String, dynamic>?;
    if (workout == null) {
      throw Exception('Missing workout in response.');
    }
    return PersonalWorkout.fromJson(workout);
  }

  @override
  Future<void> deleteWorkout({required int id}) async {
    await _dio.delete<Map<String, dynamic>>(
      '/personal-workouts',
      data: {'id': id},
      options: Options(headers: await _authHeaders()),
    );
  }

  Future<Map<String, String>> _authHeaders() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      throw Exception('No active session found.');
    }
    return {'Authorization': 'Bearer ${tokens.accessToken}'};
  }
}
