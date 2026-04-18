import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/gyms/domain/models/gym_join_request.dart';
import 'package:app/features/gyms/domain/models/my_gym_join_request.dart';
import 'package:app/features/gyms/domain/repositories/gym_repository.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final gymRepositoryProvider = Provider<GymRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiGymRepository(dio: dio, tokenStorage: tokenStorage);
});

class ApiGymRepository implements GymRepository {
  ApiGymRepository({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<List<GymSummary>> listGyms() async {
    final response = await _dio.get<Map<String, dynamic>>('/gyms');
    final gyms = response.data?['gyms'] as List<dynamic>? ?? const [];
    return gyms
        .map((gym) => _gymFromJson(gym as Map<String, dynamic>?))
        .toList();
  }

  @override
  Future<GymSummary> createGym({
    required String name,
    required String logoUrl,
    required String timezone,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/gyms',
      data: {'name': name, 'logo_url': logoUrl, 'timezone': timezone},
      options: Options(headers: await _authHeaders()),
    );
    return _gymFromJson(response.data?['gym'] as Map<String, dynamic>?);
  }

  @override
  Future<void> requestJoin({required int gymId}) async {
    await _dio.post<void>(
      '/gyms/join-requests',
      data: {'gym_id': gymId},
      options: Options(headers: await _authHeaders()),
    );
  }

  @override
  Future<List<MyGymJoinRequest>> fetchMyJoinRequests() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/gyms/my-requests',
      options: Options(headers: await _authHeaders()),
    );
    final requests = response.data?['requests'] as List<dynamic>? ?? const [];
    return requests
        .map(
          (request) => _myJoinRequestFromJson(request as Map<String, dynamic>?),
        )
        .toList();
  }

  @override
  Future<List<GymJoinRequest>> fetchJoinRequests() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/gyms/join-requests',
      options: Options(headers: await _authHeaders()),
    );
    final requests = response.data?['requests'] as List<dynamic>? ?? const [];
    return requests
        .map(
          (request) => _joinRequestFromJson(request as Map<String, dynamic>?),
        )
        .toList();
  }

  @override
  Future<void> reviewJoinRequest({
    required int requestId,
    required bool approve,
  }) async {
    await _dio.patch<void>(
      '/gyms/join-requests',
      data: {
        'request_id': requestId,
        'decision': approve ? 'approve' : 'reject',
      },
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

  GymSummary _gymFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing gym data.');
    }
    return GymSummary(
      id: data['id'] as int? ?? 0,
      name: data['name'] as String? ?? '',
      slug: data['slug'] as String? ?? '',
      logoUrl: data['logo_url'] as String? ?? '',
      timezone: data['timezone'] as String? ?? '',
    );
  }

  GymJoinRequest _joinRequestFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing join request data.');
    }
    return GymJoinRequest(
      id: data['id'] as int? ?? 0,
      email: data['email'] as String? ?? '',
      displayName: data['display_name'] as String? ?? '',
      nickname: data['nickname'] as String? ?? '',
      createdAt: data['created_at'] as String? ?? '',
    );
  }

  MyGymJoinRequest _myJoinRequestFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing join request data.');
    }
    return MyGymJoinRequest(
      id: data['id'] as int? ?? 0,
      status: data['status'] as String? ?? 'pending',
      createdAt: data['created_at'] as String? ?? '',
      reviewedAt: data['reviewed_at'] as String?,
      gym: _gymFromJson(data['gym'] as Map<String, dynamic>?),
    );
  }
}
