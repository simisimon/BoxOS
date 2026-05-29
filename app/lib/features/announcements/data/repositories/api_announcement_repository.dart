import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/network/dio_client.dart';
import 'package:app/features/announcements/domain/models/announcement.dart';
import 'package:app/features/announcements/domain/repositories/announcement_repository.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final announcementRepositoryProvider = Provider<AnnouncementRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiAnnouncementRepository(dio: dio, tokenStorage: tokenStorage);
});

class ApiAnnouncementRepository implements AnnouncementRepository {
  ApiAnnouncementRepository({
    required Dio dio,
    required TokenStorage tokenStorage,
  }) : _dio = dio,
       _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<List<Announcement>> fetchAnnouncements() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/announcements',
      options: Options(headers: await _authHeaders()),
    );
    final items = response.data?['announcements'] as List<dynamic>? ?? const [];
    return items
        .map((item) => _announcementFromJson(item as Map<String, dynamic>?))
        .toList();
  }

  @override
  Future<String> uploadAnnouncementImage({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/announcements/image',
      data: {
        'filename': filename,
        'content_type': contentType,
        'data_base64': base64Encode(bytes),
      },
      options: Options(headers: await _authHeaders()),
    );
    final imageUrl = (response.data?['image_url'] as String? ?? '').trim();
    if (imageUrl.isEmpty) {
      throw Exception('Missing uploaded image URL.');
    }
    return imageUrl;
  }

  @override
  Future<Announcement> createAnnouncement({
    required String title,
    required String description,
    String? imageUrl,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/announcements',
      data: {
        'title': title,
        'description': description,
        'image_url': imageUrl,
      },
      options: Options(headers: await _authHeaders()),
    );
    return _announcementFromJson(
      response.data?['announcement'] as Map<String, dynamic>?,
    );
  }

  @override
  Future<Announcement> updateAnnouncement({
    required int id,
    required String title,
    required String description,
    String? imageUrl,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/announcements',
      data: {
        'id': id,
        'title': title,
        'description': description,
        'image_url': imageUrl,
      },
      options: Options(headers: await _authHeaders()),
    );
    return _announcementFromJson(
      response.data?['announcement'] as Map<String, dynamic>?,
    );
  }

  @override
  Future<void> deleteAnnouncement({required int id}) async {
    await _dio.delete<void>(
      '/announcements',
      data: {'id': id},
      options: Options(headers: await _authHeaders()),
    );
  }

  @override
  Future<Announcement> likeAnnouncement({required int announcementId}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/announcements/likes',
      data: {'announcement_id': announcementId},
      options: Options(headers: await _authHeaders()),
    );
    return _announcementFromJson(
      response.data?['announcement'] as Map<String, dynamic>?,
    );
  }

  @override
  Future<Announcement> unlikeAnnouncement({required int announcementId}) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/announcements/likes',
      data: {'announcement_id': announcementId},
      options: Options(headers: await _authHeaders()),
    );
    return _announcementFromJson(
      response.data?['announcement'] as Map<String, dynamic>?,
    );
  }

  @override
  Future<AnnouncementComment> createComment({
    required int announcementId,
    required String body,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/announcements/comments',
      data: {
        'announcement_id': announcementId,
        'body': body,
      },
      options: Options(headers: await _authHeaders()),
    );
    return _commentFromJson(response.data?['comment'] as Map<String, dynamic>?);
  }

  @override
  Future<AnnouncementComment> updateComment({
    required int commentId,
    required String body,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/announcements/comments',
      data: {
        'id': commentId,
        'body': body,
      },
      options: Options(headers: await _authHeaders()),
    );
    return _commentFromJson(response.data?['comment'] as Map<String, dynamic>?);
  }

  @override
  Future<void> deleteComment({required int commentId}) async {
    await _dio.delete<void>(
      '/announcements/comments',
      data: {'id': commentId},
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

  Announcement _announcementFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing announcement data.');
    }
    final comments = data['comments'] as List<dynamic>? ?? const [];
    return Announcement(
      id: data['id'] as int? ?? 0,
      gymId: data['gym_id'] as int? ?? 0,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      imageUrl: (data['image_url'] as String?)?.trim().isEmpty ?? true
          ? null
          : data['image_url'] as String,
      authorName: data['author_name'] as String? ?? '',
      createdAt: DateTime.parse(data['created_at'] as String? ?? ''),
      updatedAt: DateTime.parse(data['updated_at'] as String? ?? ''),
      likeCount: data['like_count'] as int? ?? 0,
      likedByMe: data['liked_by_me'] as bool? ?? false,
      commentCount: data['comment_count'] as int? ?? comments.length,
      comments: comments
          .map((item) => _commentFromJson(item as Map<String, dynamic>?))
          .toList(),
      canManage: data['can_manage'] as bool? ?? false,
    );
  }

  AnnouncementComment _commentFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing announcement comment data.');
    }
    return AnnouncementComment(
      id: data['id'] as int? ?? 0,
      announcementId: data['announcement_id'] as int? ?? 0,
      authorName: data['author_name'] as String? ?? '',
      body: data['body'] as String? ?? '',
      createdAt: DateTime.parse(data['created_at'] as String? ?? ''),
      updatedAt: DateTime.parse(data['updated_at'] as String? ?? ''),
      canManage: data['can_manage'] as bool? ?? false,
    );
  }
}
