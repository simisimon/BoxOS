import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (profile?.displayName ?? '').isEmpty
                        ? (profile?.role.label ?? 'Athlete')
                        : profile!.displayName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  if ((profile?.nickname ?? '').isNotEmpty)
                    Text(
                      '@${profile!.nickname}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  const SizedBox(height: 8),
                  Text(profile?.email ?? 'No email loaded'),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text('Role: ${profile?.role.label ?? 'Athlete'}'),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text(
                      'Gym: ${profile?.activeGym?.name ?? 'Not selected'}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Account Settings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: isLoading ? null : () => context.go('/edit-profile'),
            child: const Text('Edit Profile'),
          ),
          const SizedBox(height: 8),
          if (profile?.accountType == AccountType.admin &&
              profile?.activeGym == null) ...[
            FilledButton(
              onPressed: isLoading ? null : () => context.go('/create-gym'),
              child: const Text('Create Gym'),
            ),
            const SizedBox(height: 8),
          ] else ...[
            FilledButton(
              onPressed: isLoading ? null : () => context.go('/gyms'),
              child: const Text('Find or Request Gym'),
            ),
            const SizedBox(height: 8),
          ],
          if (profile?.role == UserRole.admin) ...[
            OutlinedButton(
              onPressed: isLoading ? null : () => context.go('/role-management'),
              child: const Text('Manage Gym Members'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: isLoading ? null : () => context.go('/gym-requests'),
              child: const Text('Review Join Requests'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: isLoading
                ? null
                : () => context.go('/notification-settings'),
            child: const Text('Notification Settings'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: isLoading ? null : () => context.go('/change-password'),
            child: const Text('Change Password'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: isLoading
                ? null
                : () => ref.read(authControllerProvider.notifier).signOut(),
            child: const Text('Sign Out'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: isLoading ? null : () => context.go('/delete-account'),
            child: const Text('Delete Account'),
          ),
          if ((profile?.memberships ?? const []).isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Gym Memberships',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final membership in profile!.memberships) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        membership.gym.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Active role here: ${membership.role.label}'),
                      Text('Timezone: ${membership.gym.timezone}'),
                      const SizedBox(height: 12),
                      if (profile.activeGym?.id == membership.gym.id)
                        const Chip(label: Text('Current Gym'))
                      else
                        OutlinedButton(
                          onPressed: isLoading
                              ? null
                              : () => _switchGym(
                                  context,
                                  ref,
                                  membership.gym.id,
                                ),
                          child: const Text('Switch to This Gym'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
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
