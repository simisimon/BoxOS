import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final followsRepositoryProvider = Provider<FollowsRepository>((ref) {
  return ApiFollowsRepository(
    dio: ref.read(dioProvider),
    tokenStorage: ref.read(tokenStorageProvider),
  );
});

/// Who the athlete follows, their followers and open requests.
final followOverviewProvider = FutureProvider.autoDispose<FollowOverview>(
  (ref) => ref.watch(followsRepositoryProvider).fetchOverview(),
);

/// The friends feed, first page.
final feedProvider = FutureProvider.autoDispose<FeedPage>(
  (ref) => ref.watch(followsRepositoryProvider).fetchFeed(),
);

/// Follows across gyms (`/follows`) and the results feed (`/feed`).
abstract class FollowsRepository {
  Future<FollowOverview> fetchOverview();

  /// Members of the athlete's gyms by name.
  Future<List<FollowPerson>> search(String query);

  /// Asks to follow a gym-mate ([userId]) or anyone by [inviteCode].
  Future<FollowStatus> follow({int? userId, String? inviteCode});

  Future<void> accept(int followerId);

  /// Declines a request or removes a follower.
  Future<void> removeFollower(int followerId);

  /// Stops following, or withdraws a request.
  Future<void> unfollow(int followeeId);

  Future<FeedPage> fetchFeed({int offset = 0});
}

class ApiFollowsRepository implements FollowsRepository {
  ApiFollowsRepository({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<FollowOverview> fetchOverview() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/follows',
      options: await _options(),
    );
    return FollowOverview.fromJson(response.data ?? const {});
  }

  @override
  Future<List<FollowPerson>> search(String query) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/follows/search',
      queryParameters: {'query': query},
      options: await _options(),
    );
    return [
      for (final raw in response.data?['people'] as List? ?? const [])
        FollowPerson.fromJson(raw as Map<String, dynamic>),
    ];
  }

  @override
  Future<FollowStatus> follow({int? userId, String? inviteCode}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/follows',
      data: {'user_id': ?userId, 'invite_code': ?inviteCode},
      options: await _options(),
    );
    return FollowStatus.fromWire(response.data?['status']);
  }

  @override
  Future<void> accept(int followerId) async {
    await _dio.post<Map<String, dynamic>>(
      '/follows/requests/$followerId/accept',
      options: await _options(),
    );
  }

  @override
  Future<void> removeFollower(int followerId) async {
    await _dio.delete<Map<String, dynamic>>(
      '/follows/followers/$followerId',
      options: await _options(),
    );
  }

  @override
  Future<void> unfollow(int followeeId) async {
    await _dio.delete<Map<String, dynamic>>(
      '/follows/following/$followeeId',
      options: await _options(),
    );
  }

  @override
  Future<FeedPage> fetchFeed({int offset = 0}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/feed',
      queryParameters: {'offset': offset},
      options: await _options(),
    );
    return FeedPage.fromJson(response.data ?? const {});
  }

  Future<Options> _options() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) throw Exception('No active session found.');
    return Options(headers: {'Authorization': 'Bearer ${tokens.accessToken}'});
  }
}
