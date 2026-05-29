import 'dart:typed_data';
import 'dart:ui';

import 'package:app/core/errors/error_message.dart';
import 'package:app/features/announcements/data/repositories/api_announcement_repository.dart';
import 'package:app/features/announcements/domain/models/announcement.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<List<Announcement>> _announcementsFuture;
  late Future<List<ScheduleClass>> _scheduleFuture;

  @override
  void initState() {
    super.initState();
    _announcementsFuture = _loadAnnouncements();
    _scheduleFuture = _loadSchedule();
  }

  Future<List<Announcement>> _loadAnnouncements() {
    return ref.read(announcementRepositoryProvider).fetchAnnouncements();
  }

  Future<List<ScheduleClass>> _loadSchedule() {
    return ref.read(scheduleRepositoryProvider).fetchSchedule();
  }

  Future<void> _refreshAnnouncements() async {
    setState(() {
      _announcementsFuture = _loadAnnouncements();
    });
  }

  Future<void> _refreshSchedule() async {
    setState(() {
      _scheduleFuture = _loadSchedule();
    });
  }

  Future<void> _openAnnouncementComposer() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => const _AnnouncementComposerDialog(),
    );
    if (saved == true) {
      await _refreshAnnouncements();
    }
  }

  Future<void> _openAnnouncementEditor(Announcement announcement) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _AnnouncementComposerDialog(existing: announcement),
    );
    if (saved == true) {
      await _refreshAnnouncements();
    }
  }

  Future<void> _deleteAnnouncement(Announcement announcement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F1727),
        title: const Text('Delete announcement', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${announcement.title}"? This can’t be undone.',
          style: const TextStyle(color: Color(0xFFD7E0EE)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD64545)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref
          .read(announcementRepositoryProvider)
          .deleteAnnouncement(id: announcement.id);
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to delete announcement'),
          ),
        ),
      );
    }
  }

  Future<void> _toggleAnnouncementLike(Announcement announcement) async {
    try {
      final repository = ref.read(announcementRepositoryProvider);
      if (announcement.likedByMe) {
        await repository.unlikeAnnouncement(announcementId: announcement.id);
      } else {
        await repository.likeAnnouncement(announcementId: announcement.id);
      }
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: 'Like update failed.'))),
      );
    }
  }

  Future<void> _createAnnouncementComment(Announcement announcement, String body) async {
    try {
      await ref.read(announcementRepositoryProvider).createComment(
        announcementId: announcement.id,
        body: body,
      );
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: 'Comment could not be posted.'))),
      );
    }
  }

  Future<void> _editAnnouncementComment(AnnouncementComment comment, String body) async {
    try {
      await ref.read(announcementRepositoryProvider).updateComment(
        commentId: comment.id,
        body: body,
      );
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: 'Comment could not be updated.'))),
      );
    }
  }

  Future<void> _deleteAnnouncementComment(AnnouncementComment comment) async {
    try {
      await ref.read(announcementRepositoryProvider).deleteComment(commentId: comment.id);
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: 'Comment could not be deleted.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final notificationInboxAsync = ref.watch(notificationInboxProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final unreadNotifications = notificationInboxAsync.hasValue
        ? notificationInboxAsync.value!.unreadCount
        : 0;
    final canManageAnnouncements =
        profile?.activeGym != null &&
        (profile?.role == UserRole.admin || profile?.role == UserRole.trainer);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A0F1E),
            Color(0xFF111A2D),
            Color(0xFF0D1324),
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _HeroPanel(
            displayName: profile?.displayName ?? '',
            profileRole: profile?.role,
            activeGymName: profile?.activeGym?.name,
            unreadNotifications: unreadNotifications,
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            eyebrow: 'Booking',
            title: 'Class access',
            subtitle: 'Jump straight into booking and keep your reserved classes one swipe away.',
          ),
          const SizedBox(height: 12),
          _BookingQuickAccessRail(
            scheduleFuture: _scheduleFuture,
            hasActiveGym: profile?.activeGym != null,
            onOpenBooking: () => context.go('/my-box'),
            onRefresh: _refreshSchedule,
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            eyebrow: 'News',
            title: 'Gym pulse',
            subtitle: 'Announcements from your gym live here first, with expandable detail when you need it.',
          ),
          const SizedBox(height: 12),
          _AnnouncementRail(
            announcementsFuture: _announcementsFuture,
            canManageAnnouncements: canManageAnnouncements,
            hasActiveGym: profile?.activeGym != null,
            onCreateAnnouncement: _openAnnouncementComposer,
            onEditAnnouncement: _openAnnouncementEditor,
            onDeleteAnnouncement: _deleteAnnouncement,
            onToggleLike: _toggleAnnouncementLike,
            onCreateComment: _createAnnouncementComment,
            onEditComment: _editAnnouncementComment,
            onDeleteComment: _deleteAnnouncementComment,
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            eyebrow: 'Today',
            title: 'Readiness board',
            subtitle: 'The next class, the daily workout, and anything that needs attention.',
          ),
          const SizedBox(height: 12),
          _TodaySnapshot(
            unreadNotifications: unreadNotifications,
            profileRole: profile?.role,
          ),
          const SizedBox(height: 20),
          const _SectionTitle(
            eyebrow: 'Quick Access',
            title: 'Move fast',
            subtitle: 'Role-aware shortcuts without duplicating footer navigation.',
          ),
          const SizedBox(height: 12),
          _QuickAccessGrid(
            profileAccountType: profile?.accountType,
            profileRole: profile?.role,
            hasActiveGym: profile?.activeGym != null,
          ),
          if (profile?.accountType == AccountType.admin &&
              profile?.activeGym == null) ...[
            const SizedBox(height: 20),
            const _SectionTitle(
              eyebrow: 'Admin Setup',
              title: 'Open the floor',
              subtitle: 'Create the first gym before members, bookings, and programming can go live.',
            ),
            const SizedBox(height: 12),
            _ActionSpotlight(
              icon: Icons.storefront_outlined,
              title: 'Create Your First Gym',
              subtitle:
                  'Finish admin onboarding and unlock member flows, scheduling, and workout delivery.',
              actionLabel: 'Create Gym',
              accentColor: const Color(0xFFFF6B2C),
              onTap: () => context.go('/create-gym'),
            ),
          ],
          const SizedBox(height: 8),
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
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: const Color(0xFF7EE7C6),
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
            height: 0.96,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF64748B),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.displayName,
    required this.profileRole,
    required this.activeGymName,
    required this.unreadNotifications,
  });

  final String displayName;
  final UserRole? profileRole;
  final String? activeGymName;
  final int unreadNotifications;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleLabel = profileRole?.label ?? 'Athlete';
    final greeting = displayName.isEmpty ? roleLabel : displayName;
    final accent = _accentForRole(profileRole);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(0.32),
            const Color(0xFF111827),
            const Color(0xFF06090F),
          ],
        ),
        border: Border.all(color: const Color(0xFFD8E4F2)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.18),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -12,
            child: _GlowOrb(color: accent, size: 86),
          ),
          Positioned(
            right: 36,
            bottom: -32,
            child: _GlowOrb(
              color: const Color(0xFF7EE7C6).withOpacity(0.65),
              size: 92,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroChip(label: roleLabel, color: accent),
                  _HeroChip(
                    label: activeGymName ?? 'No active gym',
                    color: const Color(0xFF7EE7C6),
                    outlined: true,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'News',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF2563EB),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Built for the next training block.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Welcome back, $greeting. BoxOS now starts with a sharper operational snapshot instead of a generic dashboard.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF475569),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MetricBand(
                      label: 'Inbox',
                      value: unreadNotifications > 99
                          ? '99+'
                          : unreadNotifications.toString(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricBand(
                      label: 'Mode',
                      value: roleLabel.toUpperCase(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _accentForRole(UserRole? role) {
    switch (role) {
      case UserRole.admin:
        return const Color(0xFFFF6B2C);
      case UserRole.trainer:
        return const Color(0xFF5FB2FF);
      case UserRole.athlete:
      case null:
        return const Color(0xFF7EE7C6);
    }
  }
}

class _MetricBand extends StatelessWidget {
  const _MetricBand({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD8E4F2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFAAB6CB),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
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
            colors: [
              color.withOpacity(0.95),
              color.withOpacity(0.0),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
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
          color: const Color(0xFF0F172A),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TodaySnapshot extends StatelessWidget {
  const _TodaySnapshot({
    required this.unreadNotifications,
    required this.profileRole,
  });

  final int unreadNotifications;
  final UserRole? profileRole;

  @override
  Widget build(BuildContext context) {
    final rolePrompt = switch (profileRole) {
      UserRole.admin => 'Join requests, staffing, and payment alerts should surface here next.',
      UserRole.trainer => 'Coaching blocks, roster checks, and today\'s programming should surface here next.',
      _ => 'Your next booking, the daily WOD, and your logging prompt should surface here next.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FeatureCard(
          icon: Icons.calendar_month_rounded,
          eyebrow: 'Next Class',
          headline: 'No booking yet',
          body: 'Your next reserved class will appear here with cleaner hierarchy and stronger status visibility.',
          accentColor: Color(0xFF5FB2FF),
        ),
        const SizedBox(height: 12),
        const _FeatureCard(
          icon: Icons.local_fire_department_rounded,
          eyebrow: 'Today\'s WOD',
          headline: 'Not posted yet',
          body: 'Programming for the active gym will surface here with better emphasis once the real data slice lands.',
          accentColor: Color(0xFFFF6B2C),
        ),
        const SizedBox(height: 12),
        _FeatureCard(
          icon: Icons.notifications_active_rounded,
          eyebrow: 'Reminders',
          headline: unreadNotifications == 0
              ? 'Inbox clear'
              : '$unreadNotifications unread',
          body: rolePrompt,
          accentColor: const Color(0xFF7EE7C6),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.eyebrow,
    required this.headline,
    required this.body,
    required this.accentColor,
  });

  final IconData icon;
  final String eyebrow;
  final String headline;
  final String body;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8E4F2)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
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
                  eyebrow.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: accentColor,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  headline,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
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

class _AccentBadge extends StatelessWidget {
  const _AccentBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.28),
            color.withOpacity(0.12),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _BookingQuickAccessRail extends StatelessWidget {
  const _BookingQuickAccessRail({
    required this.scheduleFuture,
    required this.hasActiveGym,
    required this.onOpenBooking,
    required this.onRefresh,
  });

  final Future<List<ScheduleClass>> scheduleFuture;
  final bool hasActiveGym;
  final VoidCallback onOpenBooking;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (!hasActiveGym) {
      return _AnnouncementEmptyState(
        icon: Icons.calendar_month_outlined,
        title: 'No active gym selected',
        subtitle:
            'Pick or join a gym first, then your booking shortcut and reserved classes appear here.',
        actionLabel: null,
        onTap: null,
      );
    }

    return FutureBuilder<List<ScheduleClass>>(
      future: scheduleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _AnnouncementEmptyState(
            icon: Icons.error_outline,
            title: 'Couldn’t load your bookings',
            subtitle: errorMessageFrom(
              snapshot.error!,
              fallback: 'Class shortcuts are unavailable right now.',
            ),
            actionLabel: 'Retry',
            onTap: onRefresh,
          );
        }

        final now = DateTime.now();
        final bookedItems = (snapshot.data ?? const <ScheduleClass>[])
            .where((item) => item.isBooked && item.startTime.isAfter(now))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        return SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: bookedItems.isEmpty ? 2 : bookedItems.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _BookingLauncherCard(onTap: onOpenBooking);
              }
              if (bookedItems.isEmpty) {
                return const _BookingPlaceholderCard();
              }
              return _BookedClassCard(
                item: bookedItems[index - 1],
                onTap: onOpenBooking,
              );
            },
          ),
        );
      },
    );
  }
}

class _BookingLauncherCard extends StatelessWidget {
  const _BookingLauncherCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 184,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF6B2C), Color(0xFFE4511E), Color(0xFFB83314)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44FF6B2C),
                  blurRadius: 28,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Color(0x22FFFFFF),
                    child: Icon(Icons.add_rounded, color: const Color(0xFF0F172A), size: 26),
                  ),
                  Spacer(),
                  Text(
                    'Book a class',
                    style: TextStyle(
                      color: const Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Open the schedule and reserve your next slot fast.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(0xFFFBE7DE), height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingPlaceholderCard extends StatelessWidget {
  const _BookingPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: const Color(0xFF101827),
        border: Border.all(color: const Color(0xFFD8E4F2)),
      ),
      child: const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.event_busy_outlined,
                color: Color(0xFF5FB2FF),
                size: 26,
              ),
              SizedBox(height: 14),
              Text(
                'No class booked yet',
                style: TextStyle(
                  color: const Color(0xFF0F172A),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Reserve one and it stays pinned here for quick access.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Color(0xFFB8C4D9), height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookedClassCard extends StatelessWidget {
  const _BookedClassCard({required this.item, required this.onTap});

  final ScheduleClass item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final startLabel = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(item.startTime.toLocal()),
      alwaysUse24HourFormat: true,
    );
    final dayLabel = localizations.formatShortDate(item.startTime.toLocal());
    return SizedBox(
      width: 240,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF141E31), Color(0xFF101827)],
              ),
              border: Border.all(color: const Color(0xFFD8E4F2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _AccentBadge(
                      icon: Icons.check_circle_outline_rounded,
                      color: Color(0xFF7EE7C6),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: const Color(0x147EE7C6),
                        border: Border.all(color: const Color(0x337EE7C6)),
                      ),
                    child: const Text(
                        'BOOKED',
                        style: TextStyle(
                          color: Color(0xFF7EE7C6),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$dayLabel · $startLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.assignedTrainer == null
                      ? item.classType
                      : '${item.classType} · ${item.assignedTrainer!.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF8EA0BE),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnouncementRail extends StatelessWidget {
  const _AnnouncementRail({
    required this.announcementsFuture,
    required this.canManageAnnouncements,
    required this.hasActiveGym,
    required this.onCreateAnnouncement,
    required this.onEditAnnouncement,
    required this.onDeleteAnnouncement,
    required this.onToggleLike,
    required this.onCreateComment,
    required this.onEditComment,
    required this.onDeleteComment,
  });

  final Future<List<Announcement>> announcementsFuture;
  final bool canManageAnnouncements;
  final bool hasActiveGym;
  final Future<void> Function() onCreateAnnouncement;
  final Future<void> Function(Announcement announcement) onEditAnnouncement;
  final Future<void> Function(Announcement announcement) onDeleteAnnouncement;
  final Future<void> Function(Announcement announcement) onToggleLike;
  final Future<void> Function(Announcement announcement, String body) onCreateComment;
  final Future<void> Function(AnnouncementComment comment, String body) onEditComment;
  final Future<void> Function(AnnouncementComment comment) onDeleteComment;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Announcement>>(
      future: announcementsFuture,
      builder: (context, snapshot) {
        if (!hasActiveGym) {
          return _AnnouncementEmptyState(
            icon: Icons.campaign_outlined,
            title: 'No active gym selected',
            subtitle:
                'Announcements appear once you are inside an active gym context.',
            actionLabel: null,
            onTap: null,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _AnnouncementEmptyState(
            icon: Icons.error_outline,
            title: 'Failed to load announcements',
            subtitle: errorMessageFrom(
              snapshot.error!,
              fallback: 'Announcements could not be loaded.',
            ),
            actionLabel: canManageAnnouncements ? 'Try posting instead' : null,
            onTap: canManageAnnouncements ? onCreateAnnouncement : null,
          );
        }

        final announcements = snapshot.data ?? const <Announcement>[];
        if (announcements.isEmpty) {
          return _AnnouncementEmptyState(
            icon: Icons.campaign_outlined,
            title: 'No announcements yet',
            subtitle: canManageAnnouncements
                ? 'Post the first update so athletes see a real gym news feed instead of placeholders.'
                : 'Your coaches and admins have not posted any announcements yet.',
            actionLabel: canManageAnnouncements ? 'Create Announcement' : null,
            onTap: canManageAnnouncements ? onCreateAnnouncement : null,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canManageAnnouncements) ...[
              _AnnouncementComposerBanner(onTap: onCreateAnnouncement),
              const SizedBox(height: 12),
            ],
            for (final (index, announcement) in announcements.indexed) ...[
              _AnnouncementCard(
                announcement: announcement,
                canManage: announcement.canManage,
                onEdit: () => onEditAnnouncement(announcement),
                onDelete: () => onDeleteAnnouncement(announcement),
                onToggleLike: () => onToggleLike(announcement),
                onCreateComment: (body) => onCreateComment(announcement, body),
                onEditComment: onEditComment,
                onDeleteComment: onDeleteComment,
              ),
              if (index < announcements.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _AnnouncementComposerBanner extends StatelessWidget {
  const _AnnouncementComposerBanner({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x33FF6B2C), Color(0x22141E31)],
        ),
        border: Border.all(color: const Color(0x66FF6B2C)),
      ),
      child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          leading: const _AccentBadge(
            icon: Icons.add_comment_outlined,
            color: Color(0xFFFF6B2C),
          ),
          title: const Text(
            'Post a new announcement',
            style: TextStyle(color: const Color(0xFF0F172A), fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Share schedule changes, event reminders, or coach notes right on the home feed.',
            style: TextStyle(color: Color(0xFFB8C4D9), height: 1.45),
          ),
          trailing: const Icon(Icons.north_east_rounded, color: Color(0xFFFF6B2C)),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _AnnouncementEmptyState extends StatelessWidget {
  const _AnnouncementEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141E31), Color(0xFF101827)],
        ),
        border: Border.all(color: const Color(0xFFD8E4F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccentBadge(icon: icon, color: const Color(0xFF7EE7C6)),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF64748B),
              height: 1.45,
            ),
          ),
          if (actionLabel != null && onTap != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B2C),
                foregroundColor: Colors.white,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnnouncementCard extends StatefulWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleLike,
    required this.onCreateComment,
    required this.onEditComment,
    required this.onDeleteComment,
  });

  final Announcement announcement;
  final bool canManage;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final Future<void> Function() onToggleLike;
  final Future<void> Function(String body) onCreateComment;
  final Future<void> Function(AnnouncementComment comment, String body) onEditComment;
  final Future<void> Function(AnnouncementComment comment) onDeleteComment;

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  final TextEditingController _commentController = TextEditingController();
  bool _commentSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141E31), Color(0xFF101827)],
        ),
        border: Border.all(color: const Color(0xFFD8E4F2)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          collapsedIconColor: const Color(0xFF7EE7C6),
          iconColor: const Color(0xFF7EE7C6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.announcement.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Posted by ${widget.announcement.authorName} · ${_formatAnnouncementDate(widget.announcement.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF8EA0BE),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.canManage)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: Color(0xFFB8C4D9)),
                  color: const Color(0xFF141E31),
                  onSelected: (value) {
                    if (value == 'edit') {
                      widget.onEdit();
                    } else if (value == 'delete') {
                      widget.onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Edit announcement'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete announcement'),
                    ),
                  ],
                ),
              const SizedBox(width: 8),
            ],
          ),
          subtitle: widget.announcement.imageUrl == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        widget.announcement.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: const Color(0xFF0F1727),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: Color(0xFF8EA0BE),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          children: [
            if (widget.announcement.updatedAt.isAfter(widget.announcement.createdAt)) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Last updated ${_formatAnnouncementDate(widget.announcement.updatedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF8EA0BE),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.announcement.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF475569),
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _AnnouncementMetricButton(
                  icon: widget.announcement.likedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: '${widget.announcement.likeCount} likes',
                  accent: widget.announcement.likedByMe
                      ? const Color(0xFFFF6B6B)
                      : const Color(0xFF7EE7C6),
                  onTap: widget.onToggleLike,
                ),
                _AnnouncementStaticPill(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '${widget.announcement.commentCount} comments',
                ),
              ],
            ),
            const SizedBox(height: 18),
            _AnnouncementCommentComposer(
              controller: _commentController,
              isSubmitting: _commentSubmitting,
              onSubmit: _submitComment,
            ),
            if (widget.announcement.comments.isNotEmpty) ...[
              const SizedBox(height: 18),
              for (final (index, comment) in widget.announcement.comments.indexed) ...[
                _AnnouncementCommentCard(
                  comment: comment,
                  onEdit: () => _promptEditComment(comment),
                  onDelete: () => widget.onDeleteComment(comment),
                ),
                if (index < widget.announcement.comments.length - 1)
                  const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submitComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty || _commentSubmitting) {
      return;
    }
    setState(() => _commentSubmitting = true);
    try {
      await widget.onCreateComment(body);
      _commentController.clear();
    } finally {
      if (mounted) {
        setState(() => _commentSubmitting = false);
      }
    }
  }

  Future<void> _promptEditComment(AnnouncementComment comment) async {
    final controller = TextEditingController(text: comment.body);
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F1727),
        title: const Text('Edit comment', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Update your comment',
            hintStyle: TextStyle(color: Color(0xFF8EA0BE)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null || saved.isEmpty) {
      return;
    }
    await widget.onEditComment(comment, saved);
  }
}

class _AnnouncementMetricButton extends StatelessWidget {
  const _AnnouncementMetricButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: accent.withOpacity(0.12),
            border: Border.all(color: accent.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: const Color(0xFF0F172A), fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementStaticPill extends StatelessWidget {
  const _AnnouncementStaticPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0xFFF8FBFF),
        border: Border.all(color: const Color(0xFFD8E4F2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF8EA0BE)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: const Color(0xFF0F172A), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _AnnouncementCommentComposer extends StatelessWidget {
  const _AnnouncementCommentComposer({
    required this.controller,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isSubmitting;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFFF8FBFF),
        border: Border.all(color: const Color(0xFFD8E4F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Add a comment',
              hintStyle: TextStyle(color: Color(0xFF8EA0BE)),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: isSubmitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B2C),
                foregroundColor: Colors.white,
              ),
              icon: isSubmitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('Post'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCommentCard extends StatelessWidget {
  const _AnnouncementCommentCard({
    required this.comment,
    required this.onEdit,
    required this.onDelete,
  });

  final AnnouncementComment comment;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF0F1727),
        border: Border.all(color: const Color(0xFFD8E4F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.authorName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatAnnouncementDate(comment.updatedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF8EA0BE),
                      ),
                    ),
                  ],
                ),
              ),
              if (comment.canManage)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: Color(0xFF8EA0BE)),
                  color: const Color(0xFF141E31),
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(value: 'edit', child: Text('Edit comment')),
                    PopupMenuItem<String>(value: 'delete', child: Text('Delete comment')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            comment.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475569),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatAnnouncementDate(DateTime value) {
  final local = value.toLocal();
  final month = switch (local.month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mar',
    4 => 'Apr',
    5 => 'May',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Oct',
    11 => 'Nov',
    _ => 'Dec',
  };
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} $month · $hour:$minute';
}

class _HomeAction {
  const _HomeAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final Color accentColor;
}

class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid({
    required this.profileAccountType,
    required this.profileRole,
    required this.hasActiveGym,
  });

  final AccountType? profileAccountType;
  final UserRole? profileRole;
  final bool hasActiveGym;

  @override
  Widget build(BuildContext context) {
    final actions = <_HomeAction>[
      if (profileAccountType == AccountType.admin && profileRole == UserRole.admin)
        const _HomeAction(
          icon: Icons.group_outlined,
          title: 'Review Join Requests',
          subtitle: 'Approve or reject athletes requesting access to your gym.',
          route: '/gym-requests',
          accentColor: Color(0xFFFF6B2C),
        )
      else
        const _HomeAction(
          icon: Icons.search_outlined,
          title: 'Find a Gym',
          subtitle: 'Browse gyms and request access from the athlete flow.',
          route: '/gyms',
          accentColor: Color(0xFF7EE7C6),
        ),
      if (profileRole == UserRole.trainer || profileRole == UserRole.admin)
        const _HomeAction(
          icon: Icons.edit_calendar_outlined,
          title: 'Open Schedule',
          subtitle: 'Move into class planning and coaching workflows.',
          route: '/my-box',
          accentColor: Color(0xFF5FB2FF),
        )
      else
        const _HomeAction(
          icon: Icons.menu_book_outlined,
          title: 'Open Logbook',
          subtitle: 'Jump straight into workout history and recent efforts.',
          route: '/logbook',
          accentColor: Color(0xFF5FB2FF),
        ),
      _HomeAction(
        icon: hasActiveGym ? Icons.local_fire_department_outlined : Icons.notifications_outlined,
        title: hasActiveGym ? 'See Programming' : 'Open Notifications',
        subtitle: hasActiveGym
            ? 'Check the current WOD and upcoming training flow.'
            : 'Stay on top of inbox items until a gym is active.',
        route: hasActiveGym ? '/programming' : '/notifications',
        accentColor: const Color(0xFFB98CFF),
      ),
    ];

    return Column(
      children: [
        for (final (index, action) in actions.indexed) ...[
          _ActionTile(action: action),
          if (index < actions.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final _HomeAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1727),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8E4F2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => context.go(action.route),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _AccentBadge(icon: action.icon, color: action.accentColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        action.subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF64748B),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.north_east_rounded,
                  color: action.accentColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionSpotlight extends StatelessWidget {
  const _ActionSpotlight({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withOpacity(0.22),
            const Color(0xFF131A29),
          ],
        ),
        border: Border.all(color: accentColor.withOpacity(0.22)),
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
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onTap,
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementComposerDialog extends ConsumerStatefulWidget {
  const _AnnouncementComposerDialog({this.existing});

  final Announcement? existing;

  @override
  ConsumerState<_AnnouncementComposerDialog> createState() =>
      _AnnouncementComposerDialogState();
}

class _AnnouncementComposerDialogState
    extends ConsumerState<_AnnouncementComposerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _imagePicker = ImagePicker();
  bool _isSaving = false;
  bool _isUploadingImage = false;
  Uint8List? _selectedImageBytes;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description;
      _imageUrlController.text = existing.imageUrl ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    if (_isSaving || _isUploadingImage) {
      return;
    }
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      final contentType = switch (picked.mimeType) {
        final type? when type.trim().isNotEmpty => type,
        _ when picked.name.toLowerCase().endsWith('.png') => 'image/png',
        _ when picked.name.toLowerCase().endsWith('.webp') => 'image/webp',
        _ => 'image/jpeg',
      };
      setState(() {
        _isUploadingImage = true;
        _selectedImageBytes = bytes;
      });
      final imageUrl = await ref
          .read(announcementRepositoryProvider)
          .uploadAnnouncementImage(
            bytes: bytes,
            filename: picked.name,
            contentType: contentType,
          );
      if (!mounted) {
        return;
      }
      _imageUrlController.text = imageUrl;
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to upload image'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      final repository = ref.read(announcementRepositoryProvider);
      if (_isEditing) {
        await repository.updateAnnouncement(
          id: widget.existing!.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          imageUrl: _imageUrlController.text.trim().isEmpty
              ? null
              : _imageUrlController.text.trim(),
        );
      } else {
        await repository.createAnnouncement(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          imageUrl: _imageUrlController.text.trim().isEmpty
              ? null
              : _imageUrlController.text.trim(),
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(
              error,
              fallback: _isEditing
                  ? 'Failed to update announcement'
                  : 'Failed to create announcement',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F1727),
      title: Text(
        _isEditing ? 'Edit Announcement' : 'Create Announcement',
        style: const TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0x2218D2A8), Color(0x22FF6B2C)],
                    ),
                    border: Border.all(color: const Color(0xFFD8E4F2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add a gallery image',
                        style: TextStyle(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Pick a photo from your phone. It will upload and attach automatically.',
                        style: TextStyle(
                          color: Color(0xFFB8C4D9),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedImageBytes != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.memory(
                              _selectedImageBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _isUploadingImage
                                ? null
                                : _pickImageFromGallery,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B2C),
                              foregroundColor: Colors.white,
                            ),
                            icon: _isUploadingImage
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  )
                                : const Icon(Icons.photo_library_outlined),
                            label: Text(
                              _isUploadingImage
                                  ? 'Uploading...'
                                  : 'Choose from gallery',
                            ),
                          ),
                          if (_imageUrlController.text.trim().isNotEmpty) ...[
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _imageUrlController.clear();
                                  _selectedImageBytes = null;
                                });
                              },
                              child: const Text('Remove image'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'Saturday schedule update',
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Title is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 4,
                  maxLines: 7,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Write the actual update athletes should read.',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Description is required';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B2C),
            foregroundColor: Colors.white,
          ),
          child: Text(
            _isSaving
                ? (_isEditing ? 'Saving...' : 'Posting...')
                : (_isEditing ? 'Save Changes' : 'Post Announcement'),
          ),
        ),
      ],
    );
  }
}
