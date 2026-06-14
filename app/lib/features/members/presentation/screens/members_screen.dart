import 'dart:async';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/responsive/responsive_masonry.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/gyms/domain/models/gym_join_request.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owner-facing "Members" tab: pending join requests and the active member
/// roster with inline role management, in one place. Renders as a shell branch
/// body (the shell supplies the top header), so there is no local app bar.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  bool _loading = false;
  bool _loaded = false;
  String? _errorText;

  List<GymJoinRequest> _requests = const [];
  List<RoleManagedUser> _users = const [];

  final Map<int, List<UserRole>> _draftRoles = {};
  int? _savingUserId;
  int? _pendingRequestId;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final gymRepo = ref.read(gymRepositoryProvider);
      final profileRepo = ref.read(profileRepositoryProvider);
      final results = await Future.wait([
        gymRepo.fetchJoinRequests(),
        profileRepo.fetchRoleManagedUsers(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _requests = results[0] as List<GymJoinRequest>;
        _users = results[1] as List<RoleManagedUser>;
        _loaded = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText =
            errorMessageFrom(error, fallback: 'Failed to load members');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refresh() => _load();

  Future<void> _review(GymJoinRequest request, bool approve) async {
    setState(() => _pendingRequestId = request.id);
    try {
      await ref
          .read(gymRepositoryProvider)
          .reviewJoinRequest(requestId: request.id, approve: approve);
      if (!mounted) {
        return;
      }
      // Drop the handled request immediately; refresh the roster so an
      // approved athlete shows up as a member without a manual reload.
      setState(() {
        _requests = [
          for (final r in _requests)
            if (r.id != request.id) r,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Approved ${request.email}.' : 'Rejected ${request.email}.',
          ),
        ),
      );
      if (approve) {
        unawaited(_reloadRoster());
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessageFrom(error, fallback: 'Review failed')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingRequestId = null);
      }
    }
  }

  Future<void> _reloadRoster() async {
    try {
      final users =
          await ref.read(profileRepositoryProvider).fetchRoleManagedUsers();
      if (!mounted) {
        return;
      }
      setState(() => _users = users);
    } catch (_) {
      // Non-fatal: the roster simply keeps its previous state.
    }
  }

  List<UserRole> _rolesFor(RoleManagedUser user) =>
      _draftRoles[user.id] ?? user.availableRoles;

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
    setState(() => _draftRoles[user.id] = nextRoles);
  }

  bool _hasRoleChanges(RoleManagedUser user) {
    final draft = _draftRoles[user.id];
    if (draft == null) {
      return false;
    }
    final current = user.availableRoles.toSet();
    return !(draft.length == current.length && current.containsAll(draft));
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
          for (final u in _users)
            if (u.id == updated.id) updated else u,
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
          content: Text(errorMessageFrom(error, fallback: 'Failed to update role')),
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

    // Kick off the first load once we know the user has access.
    if (hasAccess && !_loaded && !_loading && _errorText == null) {
      Future.microtask(_load);
    }

    return DecoratedBox(
      decoration: appPageDecoration(),
      child: _buildBody(profileAsync, hasAccess),
    );
  }

  Widget _buildBody(AsyncValue<dynamic> profileAsync, bool hasAccess) {
    if (profileAsync.isLoading && !profileAsync.hasValue) {
      return const AppLoadingState();
    }
    if (!hasAccess) {
      return Padding(
        padding: const EdgeInsets.all(appSpaceLg),
        child: AppEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Owner access required',
          subtitle:
              'Switch to an active box you own to manage members and join requests.',
        ),
      );
    }
    if (_loading && !_loaded) {
      return const AppLoadingState();
    }
    if (_errorText != null && !_loaded) {
      return Padding(
        padding: const EdgeInsets.all(appSpaceLg),
        child: AppEmptyState.error(
          title: 'Could not load members',
          subtitle: _errorText,
          actionLabel: 'Retry',
          onAction: _refresh,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          appSpaceLg,
          appSpaceLg,
          appSpaceLg,
          appSpace3xl,
        ),
        children: [
          AppSectionHeader(
            title: 'Join Requests',
            eyebrow: 'Membership',
            trailing: _requests.isEmpty
                ? null
                : AppPill(
                    label: '${_requests.length}',
                    intent: AppPillIntent.warning,
                    dense: true,
                  ),
          ),
          const SizedBox(height: appSpaceMd),
          _buildRequests(),
          const SizedBox(height: appSpace2xl),
          AppSectionHeader(
            title: 'Members',
            eyebrow: 'Roster',
            trailing: _users.isEmpty
                ? null
                : AppPill(
                    label: '${_users.length}',
                    intent: AppPillIntent.primary,
                    dense: true,
                  ),
          ),
          const SizedBox(height: appSpaceMd),
          _buildRoster(),
        ],
      ),
    );
  }

  Widget _buildRequests() {
    if (_requests.isEmpty) {
      return AppEmptyState(
        icon: Icons.inbox_outlined,
        title: 'No pending requests',
        subtitle: 'New athletes asking to join your box appear here.',
        compact: true,
      );
    }
    return ResponsiveMasonry(
      minColumnWidth: 320,
      maxColumns: 3,
      spacing: appSpaceMd,
      children: [
        for (final request in _requests)
          _RequestCard(
            request: request,
            isPending: _pendingRequestId == request.id,
            onApprove: () => _review(request, true),
            onReject: () => _review(request, false),
          ),
      ],
    );
  }

  Widget _buildRoster() {
    if (_users.isEmpty) {
      return AppEmptyState(
        icon: Icons.group_outlined,
        title: 'No active members',
        subtitle: 'Approved members of your box show up here.',
        compact: true,
      );
    }
    return ResponsiveMasonry(
      minColumnWidth: 340,
      maxColumns: 3,
      spacing: appSpaceMd,
      children: [
        for (final user in _users)
          _MemberCard(
            user: user,
            draftRoles: _rolesFor(user),
            isSaving: _savingUserId == user.id,
            hasChanges: _hasRoleChanges(user),
            onToggleRole: (role, enabled) => _toggleRole(user, role, enabled),
            onSave: () => _updateRoles(user),
          ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.isPending,
    required this.onApprove,
    required this.onReject,
  });

  final GymJoinRequest request;
  final bool isPending;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName =
        request.displayName.isEmpty ? request.email : request.displayName;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppAccentBadge(
                icon: Icons.person_add_alt_1_outlined,
                color: appPrimary,
              ),
              const SizedBox(width: appSpaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      request.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                    if (request.nickname.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${request.nickname}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: appMutedText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: appSpaceLg),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: 'Reject',
                  onPressed: isPending ? null : onReject,
                  size: AppButtonSize.md,
                  busy: isPending,
                ),
              ),
              const SizedBox(width: appSpaceSm),
              Expanded(
                child: AppPrimaryButton(
                  label: 'Approve',
                  onPressed: isPending ? null : onApprove,
                  size: AppButtonSize.md,
                  busy: isPending,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.user,
    required this.draftRoles,
    required this.isSaving,
    required this.hasChanges,
    required this.onToggleRole,
    required this.onSave,
  });

  final RoleManagedUser user;
  final List<UserRole> draftRoles;
  final bool isSaving;
  final bool hasChanges;
  final void Function(UserRole role, bool enabled) onToggleRole;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName =
        user.displayName.isEmpty ? user.email : user.displayName;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(displayName: displayName, size: 40),
              const SizedBox(width: appSpaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.nickname.isEmpty ? user.email : '@${user.nickname}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                  ],
                ),
              ),
              AppPill(label: user.role.label, dense: true),
            ],
          ),
          const SizedBox(height: appSpaceLg),
          Text(
            'ROLES',
            style: theme.textTheme.labelSmall?.copyWith(
              color: appSubtleText,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: appSpaceSm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final role in const [UserRole.athlete, UserRole.trainer])
                FilterChip(
                  label: Text(role.label),
                  selected: draftRoles.contains(role),
                  onSelected: isSaving || !user.canEditRole
                      ? null
                      : (selected) => onToggleRole(role, selected),
                ),
            ],
          ),
          if (!user.canEditRole) ...[
            const SizedBox(height: appSpaceSm),
            Text(
              'Owner memberships are managed elsewhere.',
              style: theme.textTheme.bodySmall?.copyWith(color: appMutedText),
            ),
          ],
          if (user.canEditRole) ...[
            const SizedBox(height: appSpaceLg),
            Align(
              alignment: Alignment.centerRight,
              child: AppPrimaryButton(
                label: 'Save roles',
                onPressed: isSaving || !hasChanges ? null : onSave,
                size: AppButtonSize.md,
                busy: isSaving,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
