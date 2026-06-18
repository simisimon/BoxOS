import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/tracking/domain/models/trackable_workout.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final trackingRepositoryProvider = Provider<TrackingRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return TrackingRepository(dio: dio, tokenStorage: tokenStorage);
});

class TrackingRepository {
  TrackingRepository({required Dio dio, required TokenStorage tokenStorage})
      : _dio = dio,
        _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  Future<List<TrackingSession>> fetchSessions({
    required TrackableSource source,
    required String sourceKey,
    int limit = 20,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/tracking-sessions',
      queryParameters: {
        'source_kind': source.apiValue,
        'source_key': sourceKey,
        'limit': limit,
      },
      options: Options(headers: await _authHeaders()),
    );
    final items = response.data?['sessions'] as List<dynamic>? ?? const [];
    return items
        .map((item) =>
            TrackingSession.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<TrackingSession> saveSession({
    required TrackableSource source,
    required String sourceKey,
    required String workoutTitle,
    required TrackingScoreType scoreType,
    required String scoreValue,
    String? notesText,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/tracking-sessions',
      data: {
        'source_kind': source.apiValue,
        'source_key': sourceKey,
        'workout_title': workoutTitle,
        'score_type': scoreType.apiValue,
        'score_value': scoreValue,
        if (notesText != null && notesText.isNotEmpty)
          'notes_text': notesText,
      },
      options: Options(headers: await _authHeaders()),
    );
    final data = response.data?['session'] as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Missing session in response.');
    }
    return TrackingSession.fromJson(data);
  }

  Future<Map<String, String>> _authHeaders() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      throw Exception('No active session found.');
    }
    return {'Authorization': 'Bearer ${tokens.accessToken}'};
  }
}
