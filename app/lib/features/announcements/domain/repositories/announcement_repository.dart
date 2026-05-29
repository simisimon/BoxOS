import 'package:app/features/announcements/domain/models/announcement.dart';
import 'dart:typed_data';

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
}
