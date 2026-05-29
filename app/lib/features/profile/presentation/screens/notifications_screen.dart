import 'package:app/core/presentation/app_chrome.dart';
import 'dart:ui';

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
      backgroundColor: appPageBackground,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              appPageBackground,
              appPageBackgroundSoft,
              appPageBackgroundEnd,
            ],
          ),
        ),
        child: SafeArea(
          child: MobileContent(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: inboxAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const _NotificationsStateCard(
                icon: Icons.error_outline,
                title: 'Notifications could not be loaded',
                message:
                    'The inbox is temporarily unavailable. Pull to refresh or try again in a moment.',
                accentColor: appPrimary,
              ),
              data: (inbox) {
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(notificationInboxProvider);
                  },
                  child: ListView(
                    children: [
                      _NotificationsHero(
                        unreadCount: inbox.unreadCount,
                        isSubmitting: _isSubmitting,
                        onBack: () => Navigator.of(context).maybePop(),
                        onMarkAllRead: inbox.unreadCount == 0
                            ? null
                            : _markAllRead,
                      ),
                      const SizedBox(height: 16),
                      if (inbox.notifications.isEmpty)
                        const _NotificationsPlaceholder()
                      else ...[
                        _SectionTitle(
                          eyebrow: 'Inbox',
                          title: 'Live alert stream',
                          subtitle:
                              'Operational updates, workout posts, PR moments, and announcement activity stay in one cleaner notification feed.',
                          trailing: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _HeroPill(
                                label: 'Unread: ${inbox.unreadCount}',
                                color: appPrimary,
                              ),
                              const _HeroPill(
                                label: 'Workout Alerts',
                                color: appPrimary,
                              ),
                              const _HeroPill(
                                label: 'Community',
                                color: appPrimary,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...inbox.notifications.map(
                          (notification) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _NotificationCard(notification),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationsHero extends StatelessWidget {
  const _NotificationsHero({
    required this.unreadCount,
    required this.isSubmitting,
    required this.onBack,
    required this.onMarkAllRead,
  });

  final int unreadCount;
  final bool isSubmitting;
  final VoidCallback onBack;
  final VoidCallback? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accentColor = appPrimary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withOpacity(0.24), appSurface, appSurfaceAlt],
        ),
        border: Border.all(color: appBorder),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.14),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -12,
            child: _GlowOrb(color: accentColor, size: 84),
          ),
          Positioned(
            right: 38,
            bottom: -28,
            child: _GlowOrb(color: appPrimary.withOpacity(0.6), size: 88),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _HeaderIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: onBack,
                  ),
                  const _HeroPill(label: 'Notifications', color: accentColor),
                  FilledButton.tonal(
                    onPressed: isSubmitting ? null : onMarkAllRead,
                    child: Text(
                      unreadCount == 0 ? 'Inbox clear' : 'Mark all read',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Notifications',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: appPrimary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Stay on top of the box pulse.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w900,
                  height: 0.96,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Booking changes, WOD drops, waitlist moves, PR alerts, and announcement reactions now sit in a cleaner inbox with stronger visibility for unread items.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: appMutedText,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroPill(
                    label: unreadCount == 0
                        ? 'Inbox clear'
                        : '$unreadCount unread',
                    color: appPrimary,
                  ),
                  const _HeroPill(
                    label: 'Operational Feed',
                    color: appPrimary,
                    outlined: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationsPlaceholder extends StatelessWidget {
  const _NotificationsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _NotificationsStateCard(
          icon: Icons.notifications_none_rounded,
          title: 'You are all caught up',
          message:
              'Booking updates, WOD posts, waitlist changes, and PR alerts will appear here once your gym starts sending them.',
          accentColor: appPrimary,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.go('/notification-settings'),
          icon: const Icon(Icons.tune_rounded),
          label: const Text('Notification Settings'),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard(this.notification);

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = notification.createdAt.toLocal();
    final timestamp =
        '${createdAt.year.toString().padLeft(4, '0')}-'
        '${createdAt.month.toString().padLeft(2, '0')}-'
        '${createdAt.day.toString().padLeft(2, '0')} '
        '${createdAt.hour.toString().padLeft(2, '0')}:'
        '${createdAt.minute.toString().padLeft(2, '0')}';
    final isPr = notification.type == 'pr_achieved';
    final isAnnouncement =
        notification.type == 'announcement_liked' ||
        notification.type == 'announcement_commented';
    final accentColor = isPr
        ? appPrimary
        : isAnnouncement
        ? appPrimary
        : appPrimary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: notification.readAt == null
              ? accentColor.withOpacity(0.28)
              : appSurfaceAlt,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(
              notification.readAt == null ? 0.1 : 0.05,
            ),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccentBadge(
            icon: isPr
                ? Icons.emoji_events_outlined
                : notification.type == 'announcement_liked'
                ? Icons.favorite_rounded
                : notification.type == 'announcement_commented'
                ? Icons.chat_bubble_outline_rounded
                : Icons.notifications_active_outlined,
            color: accentColor,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: appText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (notification.readAt == null)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: _HeroPill(label: 'New', color: appPrimary),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  notification.body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appMutedText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  timestamp,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: appSubtleText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: appPrimary,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: appText,
            fontWeight: FontWeight.w800,
            height: 0.96,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: appSubtleText,
            height: 1.4,
          ),
        ),
        if (trailing != null) ...[const SizedBox(height: 12), trailing!],
      ],
    );
  }
}

class _NotificationsStateCard extends StatelessWidget {
  const _NotificationsStateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: appBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccentBadge(icon: icon, color: accentColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: appText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appSubtleText,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(outlined ? 0.55 : 0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: appText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: appSurfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: appBorder),
          ),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.95), color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}

class _AccentBadge extends StatelessWidget {
  const _AccentBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.28), color.withOpacity(0.12)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}
