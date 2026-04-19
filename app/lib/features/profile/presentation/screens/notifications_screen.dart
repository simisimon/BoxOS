import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _isSubmitting = false;

  Future<void> _markAllRead() async {
    if (_isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ref.read(profileRepositoryProvider).markAllNotificationsRead();
      ref.invalidate(notificationInboxProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications marked as read.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update notifications.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inboxAsync = ref.watch(notificationInboxProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _markAllRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: inboxAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Notifications could not be loaded.'),
          ),
        ),
        data: (inbox) {
          if (inbox.notifications.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No notifications yet.'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('Unread: ${inbox.unreadCount}')),
                  const Chip(label: Text('Workout Alerts: Live')),
                  const Chip(label: Text('PR Alerts: Live')),
                ],
              ),
              const SizedBox(height: 16),
              ...inbox.notifications.map(_NotificationCard.new),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard(this.notification);

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final createdAt = notification.createdAt.toLocal();
    final timestamp =
        '${createdAt.year.toString().padLeft(4, '0')}-'
        '${createdAt.month.toString().padLeft(2, '0')}-'
        '${createdAt.day.toString().padLeft(2, '0')} '
        '${createdAt.hour.toString().padLeft(2, '0')}:'
        '${createdAt.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          notification.type == 'pr_achieved'
              ? Icons.emoji_events_outlined
              : Icons.notifications_active_outlined,
        ),
        title: Row(
          children: [
            Expanded(child: Text(notification.title)),
            if (notification.readAt == null)
              const Chip(label: Text('New')),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text(notification.body),
            const SizedBox(height: 6),
            Text(timestamp),
          ],
        ),
      ),
    );
  }
}
