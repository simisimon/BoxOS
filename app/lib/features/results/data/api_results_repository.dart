import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A WOD's leaderboards, by block id.
final leaderboardProvider = FutureProvider.autoDispose
    .family<Map<int, List<LeaderboardEntry>>, int>(
      (ref, workoutId) =>
          ref.watch(resultsRepositoryProvider).fetchLeaderboard(workoutId),
    );

/// "Last times" for a block.
final resultHistoryProvider = FutureProvider.autoDispose
    .family<ResultHistory, int>(
      (ref, sectionId) =>
          ref.watch(resultsRepositoryProvider).fetchHistory(sectionId),
    );

/// Profile › Results, for all results or one movement / named workout.
final myResultsProvider = FutureProvider.autoDispose
    .family<MyResults, ResultFilter?>(
      (ref, filter) =>
          ref.watch(resultsRepositoryProvider).fetchMyResults(filter),
    );

final resultsRepositoryProvider = Provider<ResultsRepository>((ref) {
  return ApiResultsRepository(
    dio: ref.read(dioProvider),
    tokenStorage: ref.read(tokenStorageProvider),
  );
});

/// What an athlete enters for one block; the server checks it against the
/// block's score type.
class ResultDraft {
  const ResultDraft({
    required this.sectionId,
    this.score,
    this.division = ResultDivision.rx,
    this.timeCapped = false,
    this.sets,
    this.notes = '',
  });

  final int sectionId;

  /// As typed: "4:12", "7+14", "120", "62.5". Null for exercise blocks.
  final String? score;
  final ResultDivision division;
  final bool timeCapped;

  /// Exercise blocks only.
  final List<ResultSet>? sets;
  final String notes;

  Map<String, dynamic> toJson() => {
    'section_id': sectionId,
    'score': score,
    'division': division.name,
    'time_capped': timeCapped,
    if (sets != null) 'sets': [for (final set in sets!) set.toJson()],
    'notes': notes,
  };
}

abstract class ResultsRepository {
  Future<WorkoutResult> saveResult(ResultDraft draft);

  Future<void> deleteResult({required int sectionId});

  Future<Map<int, List<LeaderboardEntry>>> fetchLeaderboard(int workoutId);

  Future<ResultHistory> fetchHistory(int sectionId);

  Future<MyResults> fetchMyResults(ResultFilter? filter);
}

class ApiResultsRepository implements ResultsRepository {
  ApiResultsRepository({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<WorkoutResult> saveResult(ResultDraft draft) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/results',
      data: draft.toJson(),
      options: Options(headers: await _authHeaders()),
    );
    return WorkoutResult.fromJson(
      response.data!['result'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deleteResult({required int sectionId}) async {
    await _dio.delete<Map<String, dynamic>>(
      '/results',
      data: {'section_id': sectionId},
      options: Options(headers: await _authHeaders()),
    );
  }

  @override
  Future<Map<int, List<LeaderboardEntry>>> fetchLeaderboard(
    int workoutId,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/programming/workouts/$workoutId/leaderboard',
      options: Options(headers: await _authHeaders()),
    );
    return {
      for (final raw in response.data?['sections'] as List? ?? const [])
        ((raw as Map<String, dynamic>)['section_id'] as num).toInt(): [
          for (final entry in raw['entries'] as List? ?? const [])
            LeaderboardEntry.fromJson(entry as Map<String, dynamic>),
        ],
    };
  }

  @override
  Future<ResultHistory> fetchHistory(int sectionId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/results/history',
      queryParameters: {'section_id': sectionId},
      options: Options(headers: await _authHeaders()),
    );
    return ResultHistory.fromJson(response.data ?? const {});
  }

  @override
  Future<MyResults> fetchMyResults(ResultFilter? filter) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/results/me',
      queryParameters: {
        if (filter?.movementId != null) 'movement_id': filter!.movementId,
        if (filter != null && filter.movementId == null)
          'workout_name': filter.workoutName,
      },
      options: Options(headers: await _authHeaders()),
    );
    return MyResults.fromJson(response.data ?? const {});
  }

  Future<Map<String, String>> _authHeaders() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) throw Exception('No active session found.');
    return {'Authorization': 'Bearer ${tokens.accessToken}'};
  }
}
