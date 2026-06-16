import 'package:app/features/community/domain/models/community_dashboard.dart';
import 'package:app/features/community/domain/models/chat_message.dart';

abstract class CommunityRepository {
  Future<CommunityDashboard> fetchDashboard();

  /// Fetches messages for the active gym. When [sinceId] is provided, returns
  /// messages with id > sinceId (the polling case); otherwise returns the most
  /// recent batch.
  Future<List<ChatMessage>> fetchMessages({int? sinceId});

  Future<ChatMessage> sendMessage({required String body});

  Future<void> deleteMessage({required int id});
}
