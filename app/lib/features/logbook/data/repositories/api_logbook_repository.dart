import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/logbook/domain/models/workout_log_entry.dart';
import 'package:app/features/logbook/domain/repositories/logbook_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final logbookRepositoryProvider = Provider<LogbookRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiLogbookRepository(dio: dio, tokenStorage: tokenStorage);
});

class ApiLogbookRepository implements LogbookRepository {
  ApiLogbookRepository({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<List<WorkoutLogEntry>> fetchEntries() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/logbook/entries',
      options: Options(headers: await _authHeaders()),
    );
    final items = response.data?['entries'] as List<dynamic>? ?? const [];
    return items
        .map((item) => _fromJson(item as Map<String, dynamic>?))
        .toList();
  }

  @override
  Future<WorkoutLogEntry> submitEntry({
    required int workoutId,
    required String scoreType,
    required String scoreValue,
    required String notesText,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/logbook/entries',
      data: {
        'workout_id': workoutId,
        'score_type': scoreType,
        'score_value': scoreValue,
        'notes_text': notesText,
      },
      options: Options(headers: await _authHeaders()),
    );
    return _fromJson(response.data?['entry'] as Map<String, dynamic>?);
  }

  Future<Map<String, String>> _authHeaders() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      throw Exception('No active session found.');
    }
    return {'Authorization': 'Bearer ${tokens.accessToken}'};
  }

  WorkoutLogEntry _fromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing workout log data.');
    }
    return WorkoutLogEntry(
      id: data['id'] as int? ?? 0,
      dailyWorkoutId: data['daily_workout_id'] as int? ?? 0,
      classScheduleId: data['class_schedule_id'] as int?,
      scheduledDate: DateTime.parse(data['scheduled_date'] as String? ?? ''),
      workoutTitle: data['workout_title'] as String? ?? '',
      classTitle: data['class_title'] as String?,
      classStartTime: data['class_start_time'] == null
          ? null
          : DateTime.parse(data['class_start_time'] as String),
      scoreType: data['score_type'] as String? ?? '',
      scoreValue: (data['score_value'] as num?)?.toDouble() ?? 0,
      scoreLabel: data['score_label'] as String? ?? '',
      notesText: data['notes_text'] as String? ?? '',
      updatedAt: DateTime.parse(data['updated_at'] as String? ?? ''),
      isPr: data['is_pr'] as bool? ?? false,
      prRank: data['pr_rank'] as int?,
    );
  }
}
