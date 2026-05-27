import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: MobileContent(
            padding: EdgeInsets.zero,
            child: _NotificationsHeader(
              onBack: () => Navigator.of(context).maybePop(),
              markAllReadButton: inboxAsync.maybeWhen(
                data: (inbox) => TextButton(
                  onPressed: _isSubmitting || inbox.unreadCount == 0
                      ? null
                      : _markAllRead,
                  child: const Text('Mark all read'),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
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
            return const _NotificationsPlaceholder();
          }
          return MobileContent(
            padding: EdgeInsets.zero,
            child: ListView(
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
            ),
          );
        },
      ),
    );
  }
}

class _NotificationsHeader extends StatelessWidget {
  const _NotificationsHeader({
    required this.onBack,
    required this.markAllReadButton,
  });

  final VoidCallback onBack;
  final Widget markAllReadButton;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kToolbarHeight,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Notifications',
              style: Theme.of(context).textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          markAllReadButton,
        ],
      ),
    );
  }
}

class _NotificationsPlaceholder extends StatelessWidget {
  const _NotificationsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MobileContent(
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You are all caught up',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Booking updates, WOD posts, waitlist changes, and PR alerts will appear here once your gym starts sending them.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/notification-settings'),
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Notification Settings'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
            if (notification.readAt == null) const Chip(label: Text('New')),
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
