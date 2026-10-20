import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
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

final programmingListProvider = FutureProvider.autoDispose<List<DailyWorkout>>(
  (ref) => ref.watch(programmingRepositoryProvider).fetchWorkouts(),
);

class ApiProgrammingRepository implements ProgrammingRepository {
  ApiProgrammingRepository({
    required Dio dio,
    required TokenStorage tokenStorage,
  }) : _dio = dio,
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
  Future<WorkoutImportResult> importWorkouts(
    List<Map<String, dynamic>> rows,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/programming/workouts/import',
      data: {'rows': rows},
      options: Options(
        headers: await _authHeaders(),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final data = response.data ?? const <String, dynamic>{};
    final errors = ((data['errors'] as List<dynamic>?) ?? const []).map((item) {
      final map = item as Map<String, dynamic>;
      return WorkoutImportError(
        row: map['row'] as int? ?? 0,
        message: map['message'] as String? ?? 'Invalid row',
      );
    }).toList();
    return WorkoutImportResult(
      createdCount: data['created_count'] as int? ?? 0,
      errors: errors,
    );
  }

  @override
  Future<DailyWorkout> createWorkout({
    required DateTime scheduledDate,
    required String title,
    required List<DailyWorkoutSection> sections,
    required DailyWorkoutStatus status,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/programming/workouts',
      data: {
        'scheduled_date': _dateOnly(scheduledDate),
        'title': title,
        'sections': [for (final section in sections) section.toJson()],
        'status': dailyWorkoutStatusToWire(status),
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
    required List<DailyWorkoutSection> sections,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/programming/workouts',
      data: {
        'id': id,
        'scheduled_date': _dateOnly(scheduledDate),
        'title': title,
        'sections': [for (final section in sections) section.toJson()],
      },
      options: Options(headers: await _authHeaders()),
    );
    return _fromJson(response.data?['workout'] as Map<String, dynamic>?);
  }

  @override
  Future<DailyWorkout> publishWorkout({required int id}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/programming/workouts/publish',
      data: {'id': id},
      options: Options(headers: await _authHeaders()),
    );
    return _fromJson(response.data?['workout'] as Map<String, dynamic>?);
  }

  @override
  Future<DailyWorkout> unpublishWorkout({required int id}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/programming/workouts/unpublish',
      data: {'id': id},
      options: Options(headers: await _authHeaders()),
    );
    return _fromJson(response.data?['workout'] as Map<String, dynamic>?);
  }

  @override
  Future<DailyWorkout> duplicateWorkout({
    required DateTime sourceDate,
    required DateTime targetDate,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/programming/workouts/duplicate',
      data: {
        'source_date': _dateOnly(sourceDate),
        'target_date': _dateOnly(targetDate),
      },
      options: Options(headers: await _authHeaders()),
    );
    return _fromJson(response.data?['workout'] as Map<String, dynamic>?);
  }

  @override
  Future<DailyWorkout> submitWhiteboardResult({
    required int workoutId,
    required String scoreType,
    required String scoreValue,
    required String notesText,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/programming/whiteboard-results',
      data: {
        'workout_id': workoutId,
        'score_type': scoreType,
        'score_value': scoreValue,
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
    final publishedAtRaw = data['published_at'] as String?;
    return DailyWorkout(
      id: data['id'] as int? ?? 0,
      gymId: data['gym_id'] as int? ?? 0,
      scheduledDate: DateTime.parse(data['scheduled_date'] as String? ?? ''),
      title: data['title'] as String? ?? '',
      sections: ((data['sections'] as List<dynamic>?) ?? const [])
          .map((item) => _sectionFromJson(item as Map<String, dynamic>?))
          .toList(),
      status: parseDailyWorkoutStatus(data['status']),
      publishedAt: publishedAtRaw == null || publishedAtRaw.isEmpty
          ? null
          : DateTime.parse(publishedAtRaw),
      canEdit: data['can_edit'] as bool? ?? false,
      whiteboardResults:
          (data['whiteboard_results'] as List<dynamic>? ?? const [])
              .map((item) => _whiteboardFromJson(item as Map<String, dynamic>?))
              .toList(),
      myWhiteboardResult: data['my_whiteboard_result'] == null
          ? null
          : _whiteboardFromJson(
              data['my_whiteboard_result'] as Map<String, dynamic>?,
            ),
      myWorkoutLog: data['my_workout_log'] == null
          ? null
          : _workoutLogSummaryFromJson(
              data['my_workout_log'] as Map<String, dynamic>?,
            ),
    );
  }

  DailyWorkoutSection _sectionFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing section data.');
    }
    return DailyWorkoutSection(
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      scoreType: parseWorkoutSectionScore(data['score_type']),
    );
  }

  WhiteboardResult _whiteboardFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing whiteboard result data.');
    }
    return WhiteboardResult(
      id: data['id'] as int? ?? 0,
      userId: data['user_id'] as int? ?? 0,
      athleteName: data['athlete_name'] as String? ?? '',
      scoreType: data['score_type'] as String? ?? '',
      scoreValue: (data['score_value'] as num?)?.toDouble() ?? 0,
      scoreLabel: data['score_label'] as String? ?? '',
      notesText: data['notes_text'] as String? ?? '',
      rank: data['rank'] as int? ?? 0,
    );
  }

  WorkoutLogEntrySummary _workoutLogSummaryFromJson(
    Map<String, dynamic>? data,
  ) {
    if (data == null) {
      throw Exception('Missing workout log summary data.');
    }
    return WorkoutLogEntrySummary(
      id: data['id'] as int? ?? 0,
      scoreType: data['score_type'] as String? ?? '',
      scoreValue: (data['score_value'] as num?)?.toDouble() ?? 0,
      scoreLabel: data['score_label'] as String? ?? '',
      notesText: data['notes_text'] as String? ?? '',
      updatedAt: DateTime.parse(data['updated_at'] as String? ?? ''),
      isPr: data['is_pr'] as bool? ?? false,
      prRank: data['pr_rank'] as int?,
    );
  }

  String _dateOnly(DateTime value) {
    final utc = DateTime.utc(value.year, value.month, value.day);
    return utc.toIso8601String().split('T').first;
  }
}
