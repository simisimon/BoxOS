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
  });

  final int id;
  final int gymId;
  final String title;
  final String description;
  final String? imageUrl;
  final String authorName;
  final DateTime createdAt;
  final DateTime updatedAt;
}
