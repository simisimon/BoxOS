import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/responsive/breakpoints.dart';
import 'package:app/core/presentation/responsive/responsive_masonry.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoleManagementScreen extends ConsumerStatefulWidget {
  const RoleManagementScreen({super.key});

  @override
  ConsumerState<RoleManagementScreen> createState() =>
      _RoleManagementScreenState();
}

class _RoleManagementScreenState extends ConsumerState<RoleManagementScreen> {
  List<RoleManagedUser>? _users;
  String? _errorText;
  bool _isLoading = false;
  int? _savingUserId;
  final Map<int, List<UserRole>> _draftRoles = {};

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final users = await ref
          .read(profileRepositoryProvider)
          .fetchRoleManagedUsers();
      if (!mounted) {
        return;
      }
      setState(() => _users = users);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = errorMessageFrom(
          error,
          fallback: 'Failed to load role management data',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<UserRole> _rolesFor(RoleManagedUser user) {
    return _draftRoles[user.id] ?? user.availableRoles;
  }

  void _toggleRole(RoleManagedUser user, UserRole role, bool enabled) {
    if (!user.canEditRole) {
      return;
    }
    final nextRoles = [..._rolesFor(user)];
    if (enabled) {
      if (!nextRoles.contains(role)) {
        nextRoles.add(role);
      }
    } else {
      nextRoles.remove(role);
    }
    if (nextRoles.isEmpty) {
      return;
    }
    setState(() {
      _draftRoles[user.id] = nextRoles;
    });
  }

  Future<void> _updateRoles(RoleManagedUser user) async {
    final roles = _rolesFor(user);
    setState(() => _savingUserId = user.id);
    try {
      final updated = await ref
          .read(profileRepositoryProvider)
          .updateUserRole(userId: user.id, roles: roles);
      ref.invalidate(currentProfileProvider);
      if (!mounted) {
        return;
      }
      setState(() {
        _users = [
          for (final currentUser in _users ?? const <RoleManagedUser>[])
            if (currentUser.id == updated.id) updated else currentUser,
        ];
        _draftRoles.remove(user.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated roles for ${updated.email}.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to update role'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingUserId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasAccess =
        profile?.role == UserRole.admin && profile?.activeGym != null;

    if (hasAccess && !_isLoading && _users == null && _errorText == null) {
      Future.microtask(_loadUsers);
    }

    return AppMobileScaffold(
      title: 'Gym Members',
      eyebrow: 'Roles',
      maxWidth: context.dashboardMaxWidth,
      body: profileAsync.when(
        loading: () => const AppLoadingState(),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(appSpaceLg),
          child: AppEmptyState.error(
            title: 'Failed to load profile',
            subtitle: errorMessageFrom(error, fallback: ''),
          ),
        ),
        data: (_) {
          if (!hasAccess) {
            return Padding(
              padding: const EdgeInsets.all(appSpaceLg),
              child: AppEmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Admin access required',
                subtitle:
                    'You need an active admin gym to manage member roles.',
              ),
            );
          }

          if (_isLoading) {
            return const AppLoadingState();
          }

          if (_errorText != null) {
            return Padding(
              padding: const EdgeInsets.all(appSpaceLg),
              child: AppEmptyState.error(
                title: 'Could not load members',
                subtitle: _errorText!,
              ),
            );
          }

          final users = _users ?? const <RoleManagedUser>[];
          if (users.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(appSpaceLg),
              child: AppEmptyState(
                icon: Icons.group_outlined,
                title: 'No active members',
                subtitle:
                    'No active members were found for the selected gym.',
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(appSpaceLg),
            child: ResponsiveMasonry(
              minColumnWidth: 340,
              maxColumns: 3,
              spacing: 12,
              children: [
                for (final user in users) _userCard(context, user),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _userCard(BuildContext context, RoleManagedUser user) {
    final isSaving = _savingUserId == user.id;
    final draftRoles = _rolesFor(user);
    return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName.isEmpty
                              ? user.email
                              : user.displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (user.nickname.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('@${user.nickname}'),
                        ],
                        const SizedBox(height: 4),
                        Text(user.email),
                        const SizedBox(height: 12),
                        Text('Gym role: ${user.role.label}'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [UserRole.athlete, UserRole.trainer]
                              .map(
                                (role) => FilterChip(
                                  label: Text(role.label),
                                  selected: draftRoles.contains(role),
                                  onSelected: isSaving || !user.canEditRole
                                      ? null
                                      : (selected) {
                                          _toggleRole(user, role, selected);
                                        },
                                ),
                              )
                              .toList(),
                        ),
                        if (!user.canEditRole) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Owner memberships are managed outside this screen.',
                          ),
                        ],
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: isSaving || !user.canEditRole
                                ? null
                                : () => _updateRoles(user),
                            child: isSaving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save Role'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
  }
}
