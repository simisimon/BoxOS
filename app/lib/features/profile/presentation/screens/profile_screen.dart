import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';

import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/memberships/presentation/my_membership_card.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/gym_membership.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
            ),
            const SizedBox(height: appSpace2xl),
            // Athletes see their plan at the active box; owners manage plans
            // in the Settings tab and trainers are never limited by one.
            if (profile?.activeGym != null &&
                profile?.role == UserRole.athlete) ...[
              const MyMembershipCard(),
              const SizedBox(height: appSpace2xl),
            ],
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
            const SizedBox(height: appSpace2xl),
            _ActionSection(
              eyebrow: 'Preferences & Security',
              title: 'Keep your account tight',
              children: [
                _ActionTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notification Settings',
                  subtitle:
                      'Tune workout, booking, and payment-related alerts.',
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
  });

  final String displayName;
  final String? nickname;
  final String? email;
  final String roleLabel;
  final String? gymName;
  final String profileImageUrl;

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
        ],
      ),
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
