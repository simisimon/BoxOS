import 'dart:typed_data';

import 'package:app/features/announcements/domain/models/announcement.dart';

abstract class AnnouncementRepository {
  Future<List<Announcement>> fetchAnnouncements();

  Future<String> uploadAnnouncementImage({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  });

  Future<Announcement> createAnnouncement({
    required String title,
    required String description,
    String? imageUrl,
  });

  Future<Announcement> updateAnnouncement({
    required int id,
    required String title,
    required String description,
    String? imageUrl,
  });

  Future<void> deleteAnnouncement({required int id});

  Future<Announcement> likeAnnouncement({required int announcementId});

  Future<Announcement> unlikeAnnouncement({required int announcementId});

  Future<AnnouncementComment> createComment({
    required int announcementId,
    required String body,
  });

  Future<AnnouncementComment> updateComment({
    required int commentId,
    required String body,
  });

  Future<void> deleteComment({required int commentId});
}
