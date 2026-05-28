import 'dart:ui';

import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final notificationInboxAsync = ref.watch(notificationInboxProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final unreadNotifications = notificationInboxAsync.hasValue
        ? notificationInboxAsync.value!.unreadCount
        : 0;

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
            eyebrow: 'News',
            title: 'Gym pulse',
            subtitle: 'A sharper operational snapshot for the active BoxOS context.',
          ),
          const SizedBox(height: 12),
          const _HighlightRail(),
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
            color: Colors.white,
            height: 0.96,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFB8C4D9),
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
        border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                  color: const Color(0xFFE8EEF8),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Built for the next training block.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Welcome back, $greeting. BoxOS now starts with a sharper operational snapshot instead of a generic dashboard.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFFD7E0EE),
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
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                  color: Colors.white,
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
          color: Colors.white,
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
        border: Border.all(color: Colors.white.withOpacity(0.07)),
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
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFB8C4D9),
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

class _HighlightRail extends StatelessWidget {
  const _HighlightRail();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _NewsCard(
          icon: Icons.event_available_outlined,
          title: 'Booking State',
          subtitle:
              'Upcoming class status, attendance signals, and operational changes deserve stronger visual priority here.',
          accentColor: Color(0xFF5FB2FF),
        ),
        SizedBox(height: 12),
        _NewsCard(
          icon: Icons.leaderboard_outlined,
          title: 'Workout Highlights',
          subtitle:
              'Workout-posted and PR alerts are live in the inbox and now framed like actual product highlights instead of placeholders.',
          accentColor: Color(0xFFFF6B2C),
        ),
      ],
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF141E31),
            accentColor.withOpacity(0.12),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
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
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFB8C4D9),
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
        border: Border.all(color: Colors.white.withOpacity(0.07)),
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
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        action.subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFB8C4D9),
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
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFD7E0EE),
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
