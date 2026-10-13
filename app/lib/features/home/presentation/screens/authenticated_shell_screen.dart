import 'package:app/features/home/presentation/widgets/app_shell.dart';
import 'package:app/features/home/presentation/widgets/shell_destinations.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
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

    // The owner Dashboard (home branch) and the schedule calendar (My Box) span
    // the full width like the wireframe instead of the clamped content column.
    final isOwner = profile?.accountType == AccountType.admin &&
        profile?.role == UserRole.admin;
    final currentIndex = navigationShell.currentIndex;
    final fullBleed = currentIndex == kMyBoxBranch ||
        (currentIndex == kHomeBranch && isOwner);

    return AuthenticatedScaffold(
      selectedBranchIndex: navBranchFor(navigationShell.currentIndex),
      destinations: destinations,
      displayName: profile?.displayName ?? '',
      roleLabel: profile?.role.label ?? 'Athlete',
      availableRoles: profile?.availableRoles ?? const [UserRole.athlete],
      unreadNotifications: unreadNotifications,
      profileImageUrl: profile?.profileImageUrl ?? '',
      fullBleedBody: fullBleed,
      body: navigationShell,
      onSelectBranch: (branchIndex) =>
          navigationShell.goBranch(
            branchIndex,
            initialLocation: branchIndex == navigationShell.currentIndex,
          ),
      onHeaderProfileTap: () => navigationShell.goBranch(kProfileBranch),
      onNotificationsTap: () => context.push('/notifications'),
      onRoleSelected: (role) => _switchRole(context, ref, role),
    );
  }

  static Future<void> _switchRole(
    BuildContext context,
    WidgetRef ref,
    UserRole role,
  ) async {
    try {
      await ref.read(profileRepositoryProvider).updateActiveRole(role: role);
      ref.invalidate(currentProfileProvider);
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
