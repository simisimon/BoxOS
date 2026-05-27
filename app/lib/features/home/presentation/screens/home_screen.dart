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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle('News'),
        const SizedBox(height: 8),
        const _HighlightList(),
        const SizedBox(height: 16),
        const _SectionTitle('Today'),
        const SizedBox(height: 8),
        _TodaySnapshot(unreadNotifications: unreadNotifications),
        const SizedBox(height: 16),
        const _SectionTitle('Quick Access'),
        const SizedBox(height: 8),
        _QuickAccessRow(
          profileAccountType: profile?.accountType,
          profileRole: profile?.role,
        ),
        if (profile?.accountType == AccountType.admin &&
            profile?.activeGym == null) ...[
          const SizedBox(height: 16),
          const _SectionTitle('Admin Setup'),
          const SizedBox(height: 8),
          _ActionCard(
            icon: Icons.storefront_outlined,
            title: 'Create Your First Gym',
            subtitle:
                'Admin onboarding continues by creating a gym before members can join.',
            actionLabel: 'Create Gym',
            onTap: () => context.go('/create-gym'),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _TodaySnapshot extends StatelessWidget {
  const _TodaySnapshot({required this.unreadNotifications});

  final int unreadNotifications;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SnapshotCard(
          icon: Icons.calendar_today_outlined,
          title: 'Next Class',
          value: 'No booking yet',
          subtitle: 'Your next reserved class will appear here.',
        ),
        const SizedBox(height: 12),
        _SnapshotCard(
          icon: Icons.fitness_center_outlined,
          title: 'Today\'s WOD',
          value: 'Not posted yet',
          subtitle: 'Programming for the active gym will surface here.',
        ),
        const SizedBox(height: 12),
        _SnapshotCard(
          icon: Icons.notifications_active_outlined,
          title: 'Reminders',
          value: unreadNotifications.toString(),
          subtitle:
              'Workout and PR alerts now appear in your notification inbox.',
        ),
      ],
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconBadge(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon),
    );
  }
}

class _HomeAction {
  const _HomeAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

class _ActionList extends StatelessWidget {
  const _ActionList({required this.actions});

  final List<_HomeAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(action.route),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _IconBadge(icon: action.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(action.subtitle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightList extends StatelessWidget {
  const _HighlightList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _InfoCard(
          icon: Icons.event_available_outlined,
          title: 'Booking State',
          subtitle:
              'Upcoming class status, attendance state, and changes will be summarized here.',
        ),
        SizedBox(height: 12),
        _InfoCard(
          icon: Icons.leaderboard_outlined,
          title: 'Workout Highlights',
          subtitle:
              'Workout-posted and PR alerts are now live in the notification inbox.',
        ),
      ],
    );
  }
}

class _QuickAccessRow extends StatelessWidget {
  const _QuickAccessRow({
    required this.profileAccountType,
    required this.profileRole,
  });

  final AccountType? profileAccountType;
  final UserRole? profileRole;

  @override
  Widget build(BuildContext context) {
    final actions = [
      if (profileAccountType == AccountType.admin &&
          profileRole == UserRole.admin)
        const _HomeAction(
          icon: Icons.group_outlined,
          title: 'Review Join Requests',
          subtitle: 'Approve or reject athletes requesting access to your gym.',
          route: '/gym-requests',
        )
      else
        const _HomeAction(
          icon: Icons.search_outlined,
          title: 'Find a Gym',
          subtitle: 'Browse gyms and request access from the athlete flow.',
          route: '/gyms',
        ),
    ];

    return _ActionList(actions: actions);
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _IconBadge(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onTap, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IconBadge(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
