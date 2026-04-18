import 'package:app/features/home/presentation/widgets/app_shell.dart';
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
    final profile = profileAsync.hasValue ? profileAsync.value : null;

    return AuthenticatedScaffold(
      selectedIndex: navigationShell.currentIndex,
      displayName: profile?.displayName ?? '',
      roleLabel: profile?.role.label ?? 'Athlete',
      availableRoles: profile?.availableRoles ?? const [UserRole.athlete],
      body: navigationShell,
      onHomeTap: () => navigationShell.goBranch(0),
      onMyBoxTap: () => navigationShell.goBranch(1),
      onLogbookTap: () => navigationShell.goBranch(2),
      onProfileTap: () => navigationShell.goBranch(3),
      onHeaderProfileTap: () => navigationShell.goBranch(3),
      onNotificationsTap: () => _showComingSoon(context, 'Notifications'),
      onRoleSelected: (role) => _switchRole(context, ref, role),
    );
  }

  static void _showComingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label is not implemented yet.')));
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
