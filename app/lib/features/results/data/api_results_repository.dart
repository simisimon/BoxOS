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

/// Member details › Results: a member's results at the owner's gym.
final memberResultsProvider = FutureProvider.autoDispose
    .family<MyResults, (int, ResultFilter?)>(
      (ref, key) => ref
          .watch(resultsRepositoryProvider)
          .fetchMemberResults(key.$1, key.$2),
    );

/// Who sees the athlete's results (Profile › Results).
final resultsPrivacyProvider = FutureProvider.autoDispose<ResultsVisibility>(
  (ref) => ref.watch(resultsRepositoryProvider).fetchResultsPrivacy(),
);

/// A movement's how-to, for exercise blocks in the Log panel.
final movementInfoProvider = FutureProvider.autoDispose
    .family<MovementInfo, int>(
      (ref, movementId) =>
          ref.watch(resultsRepositoryProvider).fetchMovement(movementId),
    );

/// One result with its photo, bumps and comments.
final resultDetailProvider = FutureProvider.autoDispose
    .family<ResultDetail, int>(
      (ref, resultId) =>
          ref.watch(resultsRepositoryProvider).fetchResult(resultId),
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

  Future<MyResults> fetchMemberResults(int userId, ResultFilter? filter);

  Future<ResultsVisibility> fetchResultsPrivacy();

  Future<ResultsVisibility> saveResultsPrivacy(ResultsVisibility visibility);

  /// Every result of the athlete as CSV text.
  Future<String> exportResultsCsv();

  Future<MovementInfo> fetchMovement(int movementId);

  Future<ResultDetail> fetchResult(int resultId);

  Future<ResultDetail> setBump(int resultId, {required bool bumped});

  Future<ResultDetail> addComment(int resultId, String body);

  Future<void> deleteComment(int commentId);

  /// [dataBase64] is the image file, base64 encoded.
  Future<ResultDetail> uploadPhoto(
    int resultId, {
    required String filename,
    required String contentType,
    required String dataBase64,
  });

  Future<ResultDetail> removePhoto(int resultId);
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
  Future<MyResults> fetchMyResults(ResultFilter? filter) =>
      _fetchResults('/results/me', filter);

  @override
  Future<MyResults> fetchMemberResults(int userId, ResultFilter? filter) =>
      _fetchResults('/membership/members/$userId/results', filter);

  Future<MyResults> _fetchResults(String path, ResultFilter? filter) async {
    final response = await _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: {
        if (filter?.movementId != null) 'movement_id': filter!.movementId,
        if (filter != null && filter.movementId == null)
          'workout_name': filter.workoutName,
      },
      options: Options(headers: await _authHeaders()),
    );
    return MyResults.fromJson(response.data ?? const {});
  }

  @override
  Future<ResultsVisibility> fetchResultsPrivacy() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/profile/results-privacy',
      options: Options(headers: await _authHeaders()),
    );
    return ResultsVisibility.fromWire(response.data?['visibility']);
  }

  @override
  Future<ResultsVisibility> saveResultsPrivacy(
    ResultsVisibility visibility,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/profile/results-privacy',
      data: {'visibility': visibility.name},
      options: Options(headers: await _authHeaders()),
    );
    return ResultsVisibility.fromWire(response.data?['visibility']);
  }

  @override
  Future<String> exportResultsCsv() async {
    final response = await _dio.get<String>(
      '/results/me.csv',
      options: Options(
        headers: await _authHeaders(),
        responseType: ResponseType.plain,
      ),
    );
    return response.data ?? '';
  }

  @override
  Future<MovementInfo> fetchMovement(int movementId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/movements/$movementId',
      options: Options(headers: await _authHeaders()),
    );
    return MovementInfo.fromJson(
      response.data!['movement'] as Map<String, dynamic>,
    );
  }

  @override
  Future<ResultDetail> fetchResult(int resultId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/results/$resultId',
      options: Options(headers: await _authHeaders()),
    );
    return _detail(response.data);
  }

  @override
  Future<ResultDetail> setBump(int resultId, {required bool bumped}) async {
    final options = Options(headers: await _authHeaders());
    final response = bumped
        ? await _dio.put<Map<String, dynamic>>(
            '/results/$resultId/bump',
            options: options,
          )
        : await _dio.delete<Map<String, dynamic>>(
            '/results/$resultId/bump',
            options: options,
          );
    return _detail(response.data);
  }

  @override
  Future<ResultDetail> addComment(int resultId, String body) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/results/$resultId/comments',
      data: {'body': body},
      options: Options(headers: await _authHeaders()),
    );
    return _detail(response.data);
  }

  @override
  Future<void> deleteComment(int commentId) async {
    await _dio.delete<Map<String, dynamic>>(
      '/results/comments/$commentId',
      options: Options(headers: await _authHeaders()),
    );
  }

  @override
  Future<ResultDetail> uploadPhoto(
    int resultId, {
    required String filename,
    required String contentType,
    required String dataBase64,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/results/$resultId/photo',
      data: {
        'filename': filename,
        'content_type': contentType,
        'data_base64': dataBase64,
      },
      options: Options(headers: await _authHeaders()),
    );
    return _detail(response.data);
  }

  @override
  Future<ResultDetail> removePhoto(int resultId) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/results/$resultId/photo',
      options: Options(headers: await _authHeaders()),
    );
    return _detail(response.data);
  }

  ResultDetail _detail(Map<String, dynamic>? data) =>
      ResultDetail.fromJson(data!['result'] as Map<String, dynamic>);

  Future<Map<String, String>> _authHeaders() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) throw Exception('No active session found.');
    return {'Authorization': 'Bearer ${tokens.accessToken}'};
  }
}
