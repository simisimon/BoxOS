import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/programming/domain/repositories/programming_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final programmingRepositoryProvider = Provider<ProgrammingRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiProgrammingRepository(dio: dio, tokenStorage: tokenStorage);
});

class ApiProgrammingRepository implements ProgrammingRepository {
  ApiProgrammingRepository({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<List<DailyWorkout>> fetchWorkouts() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/programming/workouts',
      options: Options(headers: await _authHeaders()),
    );
    final items = response.data?['workouts'] as List<dynamic>? ?? const [];
    return items
        .map((item) => _fromJson(item as Map<String, dynamic>?))
        .toList();
  }

  @override
  Future<DailyWorkout> createWorkout({
    required DateTime scheduledDate,
    required String title,
    required String strengthText,
    required String metconText,
    required String notesText,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/programming/workouts',
      data: {
        'scheduled_date': _dateOnly(scheduledDate),
        'title': title,
        'strength_text': strengthText,
        'metcon_text': metconText,
        'notes_text': notesText,
      },
      options: Options(headers: await _authHeaders()),
    );
    return _fromJson(response.data?['workout'] as Map<String, dynamic>?);
  }

  @override
  Future<DailyWorkout> updateWorkout({
    required int id,
    required DateTime scheduledDate,
    required String title,
    required String strengthText,
    required String metconText,
    required String notesText,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/programming/workouts',
      data: {
        'id': id,
        'scheduled_date': _dateOnly(scheduledDate),
        'title': title,
        'strength_text': strengthText,
        'metcon_text': metconText,
        'notes_text': notesText,
      },
      options: Options(headers: await _authHeaders()),
    );
    return _fromJson(response.data?['workout'] as Map<String, dynamic>?);
  }

  Future<Map<String, String>> _authHeaders() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      throw Exception('No active session found.');
    }
    return {'Authorization': 'Bearer ${tokens.accessToken}'};
  }

  DailyWorkout _fromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing workout data.');
    }
    return DailyWorkout(
      id: data['id'] as int? ?? 0,
      gymId: data['gym_id'] as int? ?? 0,
      scheduledDate: DateTime.parse(data['scheduled_date'] as String? ?? ''),
      title: data['title'] as String? ?? '',
      strengthText: data['strength_text'] as String? ?? '',
      metconText: data['metcon_text'] as String? ?? '',
      notesText: data['notes_text'] as String? ?? '',
      canEdit: data['can_edit'] as bool? ?? false,
    );
  }

  String _dateOnly(DateTime value) {
    final utc = DateTime.utc(value.year, value.month, value.day);
    return utc.toIso8601String().split('T').first;
  }
}
