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
        .map((item) => _fromJson(item as Map<String, dynamic>?))
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
    return _fromJson(response.data?['announcement'] as Map<String, dynamic>?);
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
    return _fromJson(response.data?['announcement'] as Map<String, dynamic>?);
  }

  @override
  Future<void> deleteAnnouncement({required int id}) async {
    await _dio.delete<void>(
      '/announcements',
      data: {'id': id},
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

  Announcement _fromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing announcement data.');
    }
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
    );
  }
}
