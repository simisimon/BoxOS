import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';

import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/logbook/data/repositories/api_logbook_repository.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/gym_membership.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Weekly training-session goal driving the profile snapshot's "x/N" chip.
/// Mirrors the home screen's goal so both surfaces tell the same story.
const _weeklySessionGoal = 5;

/// At-a-glance training stats shown in the profile hero, derived from the
/// athlete's logbook so the screen reads as "alive" rather than settings-only.
class _TrainingSnapshot {
  const _TrainingSnapshot({
    required this.sessionsThisWeek,
    required this.weekStreak,
    required this.prCount,
  });

  final int sessionsThisWeek;
  final int weekStreak;
  final int prCount;
}

DateTime _weekStart(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

final _trainingSnapshotProvider = FutureProvider.autoDispose<_TrainingSnapshot>(
  (ref) async {
    final entries = await ref.read(logbookRepositoryProvider).fetchEntries();
    final thisWeekStart = _weekStart(DateTime.now());

    var sessionsThisWeek = 0;
    var prCount = 0;
    final weeksWithSessions = <DateTime>{};
    for (final entry in entries) {
      if (entry.isPr) prCount++;
      final weekStart = _weekStart(entry.scheduledDate);
      weeksWithSessions.add(weekStart);
      if (!weekStart.isBefore(thisWeekStart)) sessionsThisWeek++;
    }

    // Walk back week-by-week from the current week while sessions exist.
    var streak = 0;
    var cursor = thisWeekStart;
    while (weeksWithSessions.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 7));
    }

    return _TrainingSnapshot(
      sessionsThisWeek: sessionsThisWeek,
      weekStreak: streak,
      prCount: prCount,
    );
  },
);

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final profileAsync = ref.watch(currentProfileProvider);
    final isLoading = authState.isLoading;
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final displayName = (profile?.displayName ?? '').isEmpty
        ? (profile?.role.label ?? 'Athlete')
        : profile!.displayName;

    return AppGridBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          appSpaceLg,
          appSpaceLg,
          appSpaceLg,
          appSpace2xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProfileHero(
              displayName: displayName,
              nickname: profile?.nickname,
              email: profile?.email,
              roleLabel: profile?.role.label ?? 'Athlete',
              gymName: profile?.activeGym?.name,
              profileImageUrl: profile?.profileImageUrl ?? '',
              snapshot: profile?.activeGym == null
                  ? null
                  : ref.watch(_trainingSnapshotProvider).value,
            ),
            const SizedBox(height: appSpace2xl),
            _ActionSection(
              eyebrow: 'Account Settings',
              title: 'Control your account surface',
              children: [
                _ActionTile(
                  icon: Icons.edit_outlined,
                  title: 'Edit Profile',
                  subtitle:
                      'Update name, nickname, and personal profile details.',
                  enabled: !isLoading,
                  onTap: () => context.go('/edit-profile'),
                ),
                if (profile?.accountType == AccountType.admin &&
                    profile?.activeGym == null)
                  _ActionTile(
                    icon: Icons.storefront_outlined,
                    title: 'Create Gym',
                    subtitle:
                        'Finish the admin setup path so members and programming can go live.',
                    enabled: !isLoading,
                    onTap: () => context.go('/create-gym'),
                  )
                else
                  _ActionTile(
                    icon: Icons.search_outlined,
                    title: 'Find or Request Gym',
                    subtitle:
                        'Browse available gyms or request access from the athlete flow.',
                    enabled: !isLoading,
                    onTap: () => context.go('/gyms'),
                  ),
              ],
            ),
            if (profile?.role == UserRole.admin) ...[
              const SizedBox(height: appSpace2xl),
              _ActionSection(
                eyebrow: 'Owner',
                title: 'Operate the gym',
                children: [
                  _ActionTile(
                    icon: Icons.tune_rounded,
                    title: 'Box Settings',
                    subtitle:
                        'Scheduling rules, class types, and box configuration.',
                    enabled: !isLoading,
                    onTap: () => context.go('/box-settings'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: appSpace2xl),
            _ActionSection(
              eyebrow: 'Preferences & Security',
              title: 'Keep your account tight',
              children: [
                _ActionTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notification Settings',
                  subtitle:
                      'Tune workout, PR, booking, and payment-related alerts.',
                  enabled: !isLoading,
                  onTap: () => context.go('/notification-settings'),
                ),
                _ActionTile(
                  icon: Icons.lock_outline,
                  title: 'Change Password',
                  subtitle: 'Rotate credentials and keep access secure.',
                  enabled: !isLoading,
                  onTap: () => context.go('/change-password'),
                ),
                _ActionTile(
                  icon: Icons.logout,
                  title: 'Sign Out',
                  subtitle: 'Leave the current session on this device.',
                  enabled: !isLoading,
                  onTap: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                ),
                _ActionTile(
                  icon: Icons.delete_outline,
                  title: 'Delete Account',
                  subtitle:
                      'Permanently remove the account when you are done with BoxOS.',
                  enabled: !isLoading,
                  destructive: true,
                  onTap: () => context.go('/delete-account'),
                ),
              ],
            ),
            if ((profile?.memberships ?? const []).isNotEmpty) ...[
              const SizedBox(height: appSpace2xl),
              _ActionSection(
                eyebrow: 'Memberships',
                title: 'Switch gym context fast',
                children: [
                  for (final membership in profile!.memberships)
                    _MembershipCard(
                      membership: membership,
                      isCurrentGym: profile.activeGym?.id == membership.gym.id,
                      enabled: !isLoading,
                      onSwitch: () =>
                          _switchGym(context, ref, membership.gym.id),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Future<void> _switchGym(
    BuildContext context,
    WidgetRef ref,
    int gymId,
  ) async {
    try {
      await ref.read(profileRepositoryProvider).updateActiveGym(gymId: gymId);
      ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to switch gym.')));
    }
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.displayName,
    required this.nickname,
    required this.email,
    required this.roleLabel,
    required this.gymName,
    required this.profileImageUrl,
    this.snapshot,
  });

  final String displayName;
  final String? nickname;
  final String? email;
  final String roleLabel;
  final String? gymName;
  final String profileImageUrl;
  final _TrainingSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(appSpaceXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                displayName: displayName,
                imageUrl: profileImageUrl.isEmpty ? null : profileImageUrl,
                size: 64,
              ),
              const SizedBox(width: appSpaceLg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((nickname ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@$nickname',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: appMutedText,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      email ?? 'No email loaded',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: appSpaceLg),
          Wrap(
            spacing: appSpaceSm,
            runSpacing: appSpaceSm,
            children: [
              AppPill(label: roleLabel, intent: AppPillIntent.primary),
              AppPill(label: gymName ?? 'No gym selected'),
            ],
          ),
          if (snapshot != null) ...[
            const SizedBox(height: appSpaceLg),
            const Divider(height: 1, color: appBorder),
            const SizedBox(height: appSpaceLg),
            Row(
              children: [
                Expanded(
                  child: _SnapshotStat(
                    value:
                        '${snapshot!.sessionsThisWeek}'
                        '/$_weeklySessionGoal',
                    label: 'SESSIONS · WK',
                  ),
                ),
                _snapshotDivider,
                Expanded(
                  child: _SnapshotStat(
                    value: '${snapshot!.weekStreak}',
                    label: 'WEEK STREAK',
                  ),
                ),
                _snapshotDivider,
                Expanded(
                  child: _SnapshotStat(
                    value: '${snapshot!.prCount}',
                    label: 'PRs ALL-TIME',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static final Widget _snapshotDivider = Container(
    width: 1,
    height: 34,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: appBorder,
  );
}

/// One cell of the profile hero's training snapshot: a Chakra-display value
/// over a mono micro-label.
class _SnapshotStat extends StatelessWidget {
  const _SnapshotStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: 24,
            height: 1,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: appMono(fontSize: 9, letterSpacing: 1.2),
        ),
      ],
    );
  }
}

/// Section header followed by its cards, spaced like the other tabs.
class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.eyebrow,
    required this.title,
    required this.children,
  });

  final String eyebrow;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(eyebrow: eyebrow, title: title),
        for (final child in children) ...[
          const SizedBox(height: appSpaceSm),
          child,
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = destructive ? appDanger : appPrimary;

    return AppCard(
      onTap: enabled ? onTap : null,
      child: Row(
        children: [
          AppAccentBadge(icon: icon, color: accentColor),
          const SizedBox(width: appSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: destructive ? appDanger : appText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: appSubtleText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: appSpaceSm),
          const Icon(Icons.chevron_right_rounded, color: appSubtleText),
        ],
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({
    required this.membership,
    required this.isCurrentGym,
    required this.enabled,
    required this.onSwitch,
  });

  final GymMembership membership;
  final bool isCurrentGym;
  final bool enabled;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  membership.gym.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: appText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isCurrentGym)
                const AppPill(
                  label: 'Current Gym',
                  intent: AppPillIntent.primary,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: appSpaceSm),
          Text(
            'Active role here: ${membership.role.label}',
            style: theme.textTheme.bodyMedium?.copyWith(color: appMutedText),
          ),
          const SizedBox(height: 2),
          Text(
            'Timezone: ${membership.gym.timezone}',
            style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
          ),
          if (!isCurrentGym) ...[
            const SizedBox(height: appSpaceMd),
            OutlinedButton(
              onPressed: enabled ? onSwitch : null,
              child: const Text('Switch to This Gym'),
            ),
          ],
        ],
      ),
    );
  }
}
