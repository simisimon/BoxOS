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

final _trainingSnapshotProvider =
    FutureProvider.autoDispose<_TrainingSnapshot>((ref) async {
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
});

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

    return DecoratedBox(
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
            const SizedBox(height: 16),
            _ActionSection(
              eyebrow: 'Account Settings',
              title: 'Control your account surface',
              subtitle:
                  'Profile edits, gym switching, security, and notifications now sit in clearer action groups.',
              children: [
                _PrimaryActionTile(
                  icon: Icons.edit_outlined,
                  title: 'Edit Profile',
                  subtitle:
                      'Update name, nickname, and personal profile details.',
                  accentColor: appPrimary,
                  enabled: !isLoading,
                  onTap: () => context.go('/edit-profile'),
                ),
                const SizedBox(height: 12),
                if (profile?.accountType == AccountType.admin &&
                    profile?.activeGym == null) ...[
                  _PrimaryActionTile(
                    icon: Icons.storefront_outlined,
                    title: 'Create Gym',
                    subtitle:
                        'Finish the admin setup path so members and programming can go live.',
                    accentColor: appPrimary,
                    enabled: !isLoading,
                    onTap: () => context.go('/create-gym'),
                  ),
                ] else ...[
                  _PrimaryActionTile(
                    icon: Icons.search_outlined,
                    title: 'Find or Request Gym',
                    subtitle:
                        'Browse available gyms or request access from the athlete flow.',
                    accentColor: appPrimary,
                    enabled: !isLoading,
                    onTap: () => context.go('/gyms'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            if (profile?.role == UserRole.admin)
              _ActionSection(
                eyebrow: 'Owner',
                title: 'Operate the gym',
                subtitle:
                    'Analytics here; member management and join-request review live in the Members tab.',
                children: [
                  _SecondaryActionTile(
                    icon: Icons.insights_outlined,
                    title: 'Admin Analytics',
                    subtitle:
                        'Read attendance, utilization, and pressure at a glance.',
                    enabled: !isLoading,
                    onTap: () => context.go('/admin-analytics'),
                  ),
                  const SizedBox(height: 12),
                  _SecondaryActionTile(
                    icon: Icons.tune_rounded,
                    title: 'Box Settings',
                    subtitle:
                        'Scheduling rules, class types, and box configuration.',
                    enabled: !isLoading,
                    onTap: () => context.go('/box-settings'),
                  ),
                ],
              ),
            if (profile?.role == UserRole.admin) const SizedBox(height: 16),
            _ActionSection(
              eyebrow: 'Preferences & Security',
              title: 'Keep your account tight',
              subtitle:
                  'Notifications, password changes, and account lifecycle controls are grouped here.',
              children: [
                _SecondaryActionTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notification Settings',
                  subtitle:
                      'Tune workout, PR, booking, and payment-related alerts.',
                  enabled: !isLoading,
                  onTap: () => context.go('/notification-settings'),
                ),
                const SizedBox(height: 12),
                _SecondaryActionTile(
                  icon: Icons.lock_outline,
                  title: 'Change Password',
                  subtitle: 'Rotate credentials and keep access secure.',
                  enabled: !isLoading,
                  onTap: () => context.go('/change-password'),
                ),
                const SizedBox(height: 12),
                _SecondaryActionTile(
                  icon: Icons.logout,
                  title: 'Sign Out',
                  subtitle: 'Leave the current session on this device.',
                  enabled: !isLoading,
                  onTap: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                ),
                const SizedBox(height: 12),
                _SecondaryActionTile(
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
              const SizedBox(height: 16),
              _ActionSection(
                eyebrow: 'Memberships',
                title: 'Switch gym context fast',
                subtitle:
                    'Your active role, timezone, and current gym state are visible before switching.',
                children: [
                  for (final membership in profile!.memberships) ...[
                    _MembershipCard(
                      membership: membership,
                      isCurrentGym: profile.activeGym?.id == membership.gym.id,
                      enabled: !isLoading,
                      onSwitch: () =>
                          _switchGym(context, ref, membership.gym.id),
                    ),
                    if (membership != profile.memberships.last)
                      const SizedBox(height: 12),
                  ],
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
    const accentColor = appPrimary;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withValues(alpha: 0.24), appSurface, appSurfaceAlt],
        ),
        border: Border.all(color: appBorder),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.14),
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
            child: _GlowOrb(color: appPrimary.withValues(alpha: 0.6), size: 88),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppAvatar(
                    displayName: displayName,
                    imageUrl: profileImageUrl.isEmpty ? null : profileImageUrl,
                    size: 64,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeroPill(label: roleLabel, color: accentColor),
                        _HeroPill(
                          label: gymName ?? 'No gym selected',
                          color: appPrimary,
                          outlined: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Profile',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: appPrimary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                displayName,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w900,
                  height: 0.96,
                ),
              ),
              if ((nickname ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '@$nickname',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: appSubtleText,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                email ?? 'No email loaded',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: appMutedText,
                  height: 1.45,
                ),
              ),
              if (snapshot != null) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _SnapshotStat(
                        value: '${snapshot!.sessionsThisWeek}'
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

class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: appBorder),
      ),
      child: Column(
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
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _PrimaryActionTile extends StatelessWidget {
  const _PrimaryActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withOpacity(0.2), appSurface],
        ),
        border: Border.all(color: accentColor.withOpacity(0.22)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                AppAccentBadge(icon: icon, color: accentColor),
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
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: appMutedText,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.north_east_rounded, color: accentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryActionTile extends StatelessWidget {
  const _SecondaryActionTile({
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

    return Container(
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: appBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                AppAccentBadge(icon: icon, color: accentColor),
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
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: appSubtleText,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: accentColor),
              ],
            ),
          ),
        ),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isCurrentGym ? appPrimary.withOpacity(0.26) : appSurfaceAlt,
        ),
      ),
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
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isCurrentGym)
                const _HeroPill(label: 'Current Gym', color: appPrimary),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Active role here: ${membership.role.label}',
            style: theme.textTheme.bodyMedium?.copyWith(color: appMutedText),
          ),
          const SizedBox(height: 4),
          Text(
            'Timezone: ${membership.gym.timezone}',
            style: theme.textTheme.bodyMedium?.copyWith(color: appSubtleText),
          ),
          if (!isCurrentGym) ...[
            const SizedBox(height: 14),
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
            colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }
}
