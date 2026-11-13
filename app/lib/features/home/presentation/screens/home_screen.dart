import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/home/presentation/widgets/owner_dashboard.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _homeAccent = appPrimary;

/// Each role's start page, in the admin layout (docs/admin-ui-reference.md
/// §1): the owner's Dashboard, the trainer's Dashboard (their classes) and
/// the athlete's Home (book a class, WOD of the day, announcements).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasActiveGym = profile?.activeGym != null;
    final isOwner =
        profile?.accountType == AccountType.admin &&
        profile?.role == UserRole.admin;

    if (!hasActiveGym) {
      return AppGridBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const SizedBox(height: 40),
            isOwner
                ? _ActionSpotlight(
                    icon: Icons.storefront_outlined,
                    title: 'Create Your First Box',
                    subtitle:
                        'Set up your box to unlock member flows, scheduling, and workout delivery.',
                    actionLabel: 'Create Box',
                    accentColor: _homeAccent,
                    onTap: () => context.go('/create-gym'),
                  )
                : _ActionSpotlight(
                    icon: Icons.search_outlined,
                    title: 'Find Your Box',
                    subtitle:
                        'Join a box to see today’s training, book classes, and read its news.',
                    actionLabel: 'Browse Boxes',
                    accentColor: _homeAccent,
                    onTap: () => context.go('/gyms'),
                  ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        appSpaceLg,
        appSpaceLg,
        appSpaceLg,
        appSpace3xl,
      ),
      children: [
        if (isOwner)
          const OwnerDashboard()
        else if (profile?.role == UserRole.trainer)
          TrainerDashboard(userId: profile?.userId)
        else
          const AthleteHome(),
      ],
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
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withOpacity(0.22), appSurfaceAlt],
        ),
        border: Border.all(color: accentColor.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appMutedText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
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
