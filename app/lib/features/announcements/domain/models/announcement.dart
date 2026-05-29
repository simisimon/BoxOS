class AnnouncementComment {
  const AnnouncementComment({
    required this.id,
    required this.announcementId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.canManage,
  });

  final int id;
  final int announcementId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool canManage;
}

class Announcement {
  const Announcement({
    required this.id,
    required this.gymId,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.authorName,
    required this.createdAt,
    required this.updatedAt,
    required this.likeCount,
    required this.likedByMe,
    required this.commentCount,
    required this.comments,
    required this.canManage,
  });

  final int id;
  final int gymId;
  final String title;
  final String description;
  final String? imageUrl;
  final String authorName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int likeCount;
  final bool likedByMe;
  final int commentCount;
  final List<AnnouncementComment> comments;
  final bool canManage;
}
