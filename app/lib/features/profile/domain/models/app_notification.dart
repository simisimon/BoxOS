class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.entityType,
    required this.entityId,
    required this.readAt,
    required this.createdAt,
  });

  final int id;
  final String type;
  final String title;
  final String body;
  final String? entityType;
  final int? entityId;
  final DateTime? readAt;
  final DateTime createdAt;
}

class NotificationInbox {
  const NotificationInbox({
    required this.unreadCount,
    required this.notifications,
  });

  final int unreadCount;
  final List<AppNotification> notifications;
}
