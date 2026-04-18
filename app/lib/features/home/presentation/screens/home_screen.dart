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
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final activeGymName = profile?.activeGym?.name ?? 'No gym selected';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroCard(
          roleLabel: profile?.role.label ?? 'Athlete',
          displayName: profile?.displayName ?? '',
          nickname: profile?.nickname ?? '',
          activeGymName: activeGymName,
        ),
        const SizedBox(height: 16),
        const _SectionTitle('Today'),
        const SizedBox(height: 8),
        const _TodaySnapshot(),
        const SizedBox(height: 16),
        const _SectionTitle('Highlights'),
        const SizedBox(height: 8),
        const _HighlightList(),
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

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.roleLabel,
    required this.displayName,
    required this.nickname,
    required this.activeGymName,
  });

  final String roleLabel;
  final String displayName;
  final String nickname;
  final String activeGymName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today at a glance',
            style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            displayName.isEmpty ? 'Athlete' : displayName,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (nickname.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '@$nickname',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Role: $roleLabel')),
              Chip(label: Text('Gym: $activeGymName')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _TodaySnapshot extends StatelessWidget {
  const _TodaySnapshot();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SnapshotCard(
          icon: Icons.calendar_today_outlined,
          title: 'Next Class',
          value: 'No booking yet',
          subtitle: 'Your next reserved class will appear here.',
        ),
        _SnapshotCard(
          icon: Icons.fitness_center_outlined,
          title: 'Today\'s WOD',
          value: 'Not posted yet',
          subtitle: 'Programming for the active gym will surface here.',
        ),
        _SnapshotCard(
          icon: Icons.notifications_active_outlined,
          title: 'Reminders',
          value: '0',
          subtitle: 'Booking, waitlist, and gym reminders are planned.',
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
    return SizedBox(
      width: 212,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(subtitle),
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
              'Daily shoutouts, gym highlights, and whiteboard moments can surface here later.',
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
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _ActionCard(
          icon: Icons.store_mall_directory_outlined,
          title: 'Open MyBox',
          subtitle:
              'Go to schedules, class booking, WOD planning, and gym-specific activity.',
          actionLabel: 'Go to MyBox',
          onTap: () => context.go('/my-box'),
        ),
        _ActionCard(
          icon: Icons.menu_book_outlined,
          title: 'Open Logbook',
          subtitle:
              'See workout history, benchmarks, and PR tracking as these features land.',
          actionLabel: 'Go to Logbook',
          onTap: () => context.go('/logbook'),
        ),
        if (profileAccountType == AccountType.admin &&
            profileRole == UserRole.admin)
          _ActionCard(
            icon: Icons.group_outlined,
            title: 'Review Join Requests',
            subtitle: 'Approve or reject athletes requesting access to your gym.',
            actionLabel: 'Open Requests',
            onTap: () => context.go('/gym-requests'),
          )
        else
          _ActionCard(
            icon: Icons.search_outlined,
            title: 'Find a Gym',
            subtitle: 'Browse gyms and request access from the athlete flow.',
            actionLabel: 'Browse Gyms',
            onTap: () => context.go('/gyms'),
          ),
      ],
    );
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
    return SizedBox(
      width: 212,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(subtitle),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onTap,
                child: Text(actionLabel),
              ),
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
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon),
            ),
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
