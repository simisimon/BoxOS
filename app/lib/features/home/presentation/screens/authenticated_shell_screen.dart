import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/home/presentation/widgets/app_shell.dart';
import 'package:app/features/home/presentation/widgets/shell_destinations.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AuthenticatedShellScreen extends ConsumerWidget {
  const AuthenticatedShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final notificationInboxAsync = ref.watch(notificationInboxProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final unreadNotifications = notificationInboxAsync.hasValue
        ? notificationInboxAsync.value!.unreadCount
        : 0;

    final destinations = destinationsForView(
      accountType: profile?.accountType,
      role: profile?.role,
    );

    // Only roles with a Members tab (owners) may read join requests.
    final hasMembersTab = destinations.any(
      (destination) => destination.branchIndex == kMembersBranch,
    );
    // Join requests and plan requests share the Requests segment and badge.
    final openJoinRequests = hasMembersTab
        ? (ref.watch(pendingJoinRequestsProvider).value?.length ?? 0) +
              (ref.watch(pendingPlanRequestsProvider).value?.length ?? 0)
        : 0;

    // The schedule week and views migrated to the admin layout
    // (docs/admin-ui-reference.md) span the full width; the rest keep the
    // clamped content column until their migration.
    final fullBleed =
        const {
          kMyBoxBranch,
          kMembersBranch,
          kMembershipsBranch,
          kProgramsBranch,
          kReportsBranch,
          kMessagesBranch,
          kBoxSettingsBranch,
        }.contains(navigationShell.currentIndex) ||
        // The owner dashboard is migrated; the athlete home is not yet.
        (navigationShell.currentIndex == kHomeBranch &&
            isOwnerView(
              accountType: profile?.accountType,
              role: profile?.role,
            ));

    return AuthenticatedScaffold(
      selectedBranchIndex: navBranchFor(navigationShell.currentIndex),
      destinations: destinations,
      displayName: profile?.displayName ?? '',
      roleLabel: profile?.role.label ?? 'Athlete',
      availableRoles: profile?.availableRoles ?? const [UserRole.athlete],
      unreadNotifications: unreadNotifications,
      profileImageUrl: profile?.profileImageUrl ?? '',
      email: profile?.email ?? '',
      gymName: profile?.activeGym?.name ?? '',
      gyms: [for (final m in profile?.memberships ?? const []) m.gym],
      activeGymId: profile?.activeGym?.id,
      onGymSelected: (gymId) => _switchGym(context, ref, gymId),
      onSignOut: () => ref.read(authControllerProvider.notifier).signOut(),
      fullBleedBody: fullBleed,
      branchBadges: {kMembersBranch: openJoinRequests},
      currentLocation: GoRouterState.of(context).uri.toString(),
      onNavigate: (location) => context.go(location),
      body: navigationShell,
      onSelectBranch: (branchIndex) => navigationShell.goBranch(
        branchIndex,
        initialLocation: branchIndex == navigationShell.currentIndex,
      ),
      onHeaderProfileTap: () => navigationShell.goBranch(kProfileBranch),
      onNotificationsTap: () => context.push('/notifications'),
      onRoleSelected: (role) => _switchRole(context, ref, role),
    );
  }

  Future<void> _switchGym(
    BuildContext context,
    WidgetRef ref,
    int gymId,
  ) async {
    try {
      await ref.read(profileRepositoryProvider).updateActiveGym(gymId: gymId);
      ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to switch gym.')));
    }
  }

  Future<void> _switchRole(
    BuildContext context,
    WidgetRef ref,
    UserRole role,
  ) async {
    try {
      await ref.read(profileRepositoryProvider).updateActiveRole(role: role);
      ref.invalidate(currentProfileProvider);
      // Each role has its own tab set (the owner's Members tab, for one, is
      // not an athlete tab), so land on the new role's start page instead of
      // leaving the previous role's screen open.
      navigationShell.goBranch(kHomeBranch, initialLocation: true);
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to switch role.')));
    }
  }
}
