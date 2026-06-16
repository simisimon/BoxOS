class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.deletedAt,
    required this.isOwn,
    required this.senderId,
    required this.senderDisplayName,
    required this.senderNickname,
  });

  final int id;
  final String body;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final bool isOwn;
  final int? senderId;
  final String senderDisplayName;
  final String senderNickname;

  bool get isDeleted => deletedAt != null;

  /// What to show as the sender. Falls back gracefully when the user was
  /// removed (FK SET NULL) or the display name was never set.
  String get senderLabel {
    if (senderId == null) return 'Former member';
    if (senderDisplayName.trim().isNotEmpty) return senderDisplayName;
    if (senderNickname.trim().isNotEmpty) return senderNickname;
    return 'Member';
  }
}
