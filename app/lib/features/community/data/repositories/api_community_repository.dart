import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/community/domain/models/chat_message.dart';
import 'package:app/features/community/domain/models/community_dashboard.dart';
import 'package:app/features/community/domain/repositories/community_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final communityRepositoryProvider = Provider<CommunityRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiCommunityRepository(dio: dio, tokenStorage: tokenStorage);
});

class ApiCommunityRepository implements CommunityRepository {
  ApiCommunityRepository({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<CommunityDashboard> fetchDashboard() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/community/dashboard',
      options: Options(headers: await _authHeaders()),
    );
    return _dashboardFromJson(response.data);
  }

  @override
  Future<List<ChatMessage>> fetchMessages({int? sinceId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/community/messages',
      queryParameters: sinceId == null ? null : {'since_id': sinceId},
      options: Options(headers: await _authHeaders()),
    );
    final items = response.data?['messages'] as List<dynamic>? ?? const [];
    return items
        .map((item) => _fromJson(item as Map<String, dynamic>?))
        .toList();
  }

  @override
  Future<ChatMessage> sendMessage({required String body}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/community/messages',
      data: {'body': body},
      options: Options(headers: await _authHeaders()),
    );
    return _fromJson(response.data?['message'] as Map<String, dynamic>?);
  }

  @override
  Future<void> deleteMessage({required int id}) async {
    await _dio.delete<void>(
      '/community/messages/$id',
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

  ChatMessage _fromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing chat message data.');
    }
    final deletedAtRaw = data['deleted_at'] as String?;
    final sender = (data['sender'] as Map<String, dynamic>?) ?? const {};
    return ChatMessage(
      id: data['id'] as int? ?? 0,
      body: data['body'] as String? ?? '',
      createdAt: DateTime.parse(data['created_at'] as String? ?? '').toLocal(),
      deletedAt: deletedAtRaw == null || deletedAtRaw.isEmpty
          ? null
          : DateTime.parse(deletedAtRaw).toLocal(),
      isOwn: data['is_own'] as bool? ?? false,
      senderId: sender['id'] as int?,
      senderDisplayName: sender['display_name'] as String? ?? '',
      senderNickname: sender['nickname'] as String? ?? '',
    );
  }

  CommunityDashboard _dashboardFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing community dashboard data.');
    }
    final stats = (data['stats'] as Map<String, dynamic>?) ?? const {};
    final prs = data['newest_prs'] as List<dynamic>? ?? const [];
    return CommunityDashboard(
      stats: CommunityStats(
        activeMembers: (stats['active_members'] as num?)?.toInt() ?? 0,
        activeTrainers: (stats['active_trainers'] as num?)?.toInt() ?? 0,
        owners: (stats['owners'] as num?)?.toInt() ?? 0,
        prsLast30Days: (stats['prs_last_30_days'] as num?)?.toInt() ?? 0,
        messagesLast7Days:
            (stats['messages_last_7_days'] as num?)?.toInt() ?? 0,
      ),
      newestPrs: prs
          .map((item) => _prFromJson(item as Map<String, dynamic>?))
          .toList(),
    );
  }

  CommunityPr _prFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing PR data.');
    }
    return CommunityPr(
      userId: (data['user_id'] as num?)?.toInt() ?? 0,
      displayName: data['display_name'] as String? ?? '',
      nickname: data['nickname'] as String? ?? '',
      workoutTitle: data['workout_title'] as String? ?? '',
      scoreLabel: data['score_label'] as String? ?? '',
      updatedAt: DateTime.parse(data['updated_at'] as String? ?? '').toLocal(),
    );
  }
}
