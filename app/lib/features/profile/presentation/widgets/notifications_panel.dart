import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifications as a right-side panel (docs/admin-ui-reference.md §13):
/// All | Unread, "Mark all as read", items grouped Today / Earlier. Tapping
/// an item closes the panel and calls [onOpen] with the item, so the caller
/// can navigate to what it is about.
Future<void> showNotificationsPanel(
  BuildContext context, {
  required ValueChanged<AppNotification> onOpen,
}) {
  ProviderScope.containerOf(context).invalidate(notificationInboxProvider);
  return showAppSidePanel<void>(
    context,
    width: 440,
    builder: (_) => _NotificationsPanel(onOpen: onOpen),
  );
}

class _NotificationsPanel extends ConsumerStatefulWidget {
  const _NotificationsPanel({required this.onOpen});

  final ValueChanged<AppNotification> onOpen;

  @override
  ConsumerState<_NotificationsPanel> createState() =>
      _NotificationsPanelState();
}

class _NotificationsPanelState extends ConsumerState<_NotificationsPanel> {
  bool _unreadOnly = false;
  bool _marking = false;

  Future<void> _markAllRead() async {
    setState(() => _marking = true);
    try {
      await ref.read(profileRepositoryProvider).markAllNotificationsRead();
      ref.invalidate(notificationInboxProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to update notifications'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(notificationInboxProvider);
    final unread = inbox.value?.unreadCount ?? 0;
    return AppSidePanel(
      title: 'Notifications',
      bodyPadding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: appSpaceSm,
              runSpacing: appSpaceSm,
              children: [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: false, label: Text('All')),
                    ButtonSegment(value: true, label: Text('Unread $unread')),
                  ],
                  selected: {_unreadOnly},
                  onSelectionChanged: (s) =>
                      setState(() => _unreadOnly = s.first),
                ),
                TextButton(
                  onPressed: unread == 0 || _marking ? null : _markAllRead,
                  child: const Text('Mark all as read'),
                ),
              ],
            ),
          ),
          inbox.when(
            loading: () => const AppLoadingState(height: 160),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                errorMessageFrom(
                  error,
                  fallback: 'Could not load notifications',
                ),
                style: const TextStyle(color: appSubtleText),
              ),
            ),
            data: (inbox) {
              final items = [
                for (final n in inbox.notifications)
                  if (!_unreadOnly || n.readAt == null) n,
              ];
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _unreadOnly ? 'No unread notifications.' : 'Nothing yet.',
                    style: const TextStyle(color: appSubtleText),
                  ),
                );
              }
              final now = DateTime.now();
              bool isToday(AppNotification n) {
                final t = n.createdAt.toLocal();
                return t.year == now.year &&
                    t.month == now.month &&
                    t.day == now.day;
              }

              final today = items.where(isToday).toList();
              final earlier = items.where((n) => !isToday(n)).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (label, group) in [
                    ('Today', today),
                    ('Earlier', earlier),
                  ])
                    if (group.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text(
                          label.toUpperCase(),
                          style: appMono(fontSize: 10),
                        ),
                      ),
                      for (final n in group)
                        _NotificationRow(
                          notification: n,
                          now: now,
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onOpen(n);
                          },
                        ),
                    ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.notification,
    required this.now,
    required this.onTap,
  });

  final AppNotification notification;
  final DateTime now;
  final VoidCallback onTap;

  static IconData _icon(String type) => switch (type) {
    'pr_achieved' => Icons.emoji_events_outlined,
    'announcement_liked' => Icons.favorite_border_rounded,
    'announcement_commented' => Icons.chat_bubble_outline_rounded,
    'booking_confirmed' ||
    'waitlist_promoted' ||
    'waitlist_skipped' ||
    'schedule_updated' => Icons.event_outlined,
    'wod_posted' || 'wod_updated' => Icons.fitness_center_rounded,
    'membership_plan' => Icons.credit_card_outlined,
    _ => Icons.notifications_none_rounded,
  };

  String _relative() {
    final diff = now.difference(notification.createdAt.toLocal());
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final unread = notification.readAt == null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _icon(notification.type),
              size: 18,
              color: unread ? appPrimary : appSubtleText,
            ),
            const SizedBox(width: appSpaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: appText,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13.5,
                    ),
                  ),
                  if (notification.body.isNotEmpty)
                    Text(
                      notification.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: appMutedText,
                        fontSize: 12.5,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: appSpaceSm),
            Text(
              _relative(),
              style: const TextStyle(color: appSubtleText, fontSize: 12),
            ),
            const SizedBox(width: appSpaceSm),
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                color: unread ? appPrimary : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
