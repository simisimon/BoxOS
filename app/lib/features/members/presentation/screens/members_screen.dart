import 'dart:async';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/responsive/responsive_masonry.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/gyms/domain/models/gym_join_request.dart';
import 'package:app/features/members/presentation/widgets/member_roster.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owner-facing "Members" tab: pending join requests on top, then the active
/// member roster as a search-and-filter table with inline-expand editing.
/// Renders as a shell branch body (the shell supplies the top header), so
/// there is no local app bar.
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

  int? _pendingRequestId;

  /// Members and join requests share the page as two tabs.
  bool _showRequests = false;

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
      if (!mounted) return;
      // Keep the Members tab badge in step with what this screen shows.
      ref.invalidate(pendingJoinRequestsProvider);
      setState(() {
        _requests = results[0] as List<GymJoinRequest>;
        _users = results[1] as List<RoleManagedUser>;
        _loaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText =
            errorMessageFrom(error, fallback: 'Failed to load members');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() => _load();

  Future<void> _review(GymJoinRequest request, bool approve) async {
    setState(() => _pendingRequestId = request.id);
    try {
      await ref
          .read(gymRepositoryProvider)
          .reviewJoinRequest(requestId: request.id, approve: approve);
      if (!mounted) return;
      ref.invalidate(pendingJoinRequestsProvider);
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessageFrom(error, fallback: 'Review failed')),
        ),
      );
    } finally {
      if (mounted) setState(() => _pendingRequestId = null);
    }
  }

  Future<void> _reloadRoster() async {
    try {
      final users =
          await ref.read(profileRepositoryProvider).fetchRoleManagedUsers();
      if (!mounted) return;
      setState(() => _users = users);
    } catch (_) {
      // Non-fatal: the roster simply keeps its previous state.
    }
  }

  /// Persists a single-member draft. Returns when the PATCH resolves so the
  /// roster widget can clear its in-flight spinner. Updates the local roster
  /// in place; a removed member disappears from the list entirely.
  Future<void> _saveDraft(MemberDraft draft) async {
    try {
      final updated = await ref.read(profileRepositoryProvider).updateUserRole(
            userId: draft.user.id,
            roles: draft.roles.toList(),
            activeRole: draft.activeRole,
            status: draft.status,
            adminNote: draft.adminNote,
          );
      ref.invalidate(currentProfileProvider);
      if (!mounted) return;
      setState(() {
        final next = <RoleManagedUser>[];
        for (final u in _users) {
          if (u.id != updated.id) {
            next.add(u);
          } else if (updated.status != MembershipStatus.removed) {
            next.add(updated);
          }
        }
        _users = next;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${updated.email}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to update member'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasAccess =
        profile?.role == UserRole.admin && profile?.activeGym != null;

    if (hasAccess && !_loaded && !_loading && _errorText == null) {
      Future.microtask(_load);
    }

    return AppGridBackground(
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

    // The page itself does not scroll: below the tabs, the member list and
    // the member detail each scroll on their own.
    return Padding(
      padding: const EdgeInsets.fromLTRB(appSpaceLg, appSpaceLg, appSpaceLg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.group_outlined),
                  label: Text('Members (${_users.length})'),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text('Requests (${_requests.length})'),
                ),
              ],
              selected: {_showRequests},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _showRequests = selection.first),
            ),
          ),
          const SizedBox(height: appSpaceMd),
          Expanded(
            child: _showRequests ? _buildRequestsTab() : _buildMembersTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersTab() {
    if (_users.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: AppEmptyState(
          icon: Icons.group_outlined,
          title: 'No active members',
          subtitle: 'Approved members of your box show up here.',
          compact: true,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoleMixSummary(users: _users),
        const SizedBox(height: appSpaceMd),
        Expanded(
          child: MemberRoster(
            users: _users,
            onSave: _saveDraft,
            onRefresh: _refresh,
          ),
        ),
      ],
    );
  }

  Widget _buildRequestsTab() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: appSpace3xl),
        children: [_buildRequests()],
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
}

/// Role-mix summary — athlete / trainer / admin headcounts drawn from the
/// active roster, so large boxes read their composition at a glance before
/// diving into the searchable table.
class _RoleMixSummary extends StatelessWidget {
  const _RoleMixSummary({required this.users});

  final List<RoleManagedUser> users;

  @override
  Widget build(BuildContext context) {
    var athletes = 0;
    var trainers = 0;
    var admins = 0;
    for (final user in users) {
      switch (user.role) {
        case UserRole.athlete:
          athletes++;
        case UserRole.trainer:
          trainers++;
        case UserRole.admin:
          admins++;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: appSpaceLg,
        vertical: appSpaceMd,
      ),
      decoration: appPanelDecoration(radius: appRadiusMd),
      child: Row(
        children: [
          Expanded(
            child: _RoleMixCell(count: athletes, label: 'ATHLETES'),
          ),
          _roleMixDivider,
          Expanded(
            child: _RoleMixCell(count: trainers, label: 'TRAINERS'),
          ),
          _roleMixDivider,
          Expanded(
            child: _RoleMixCell(count: admins, label: 'ADMINS'),
          ),
        ],
      ),
    );
  }

  static final Widget _roleMixDivider = Container(
    width: 1,
    height: 34,
    margin: const EdgeInsets.symmetric(horizontal: appSpaceSm),
    color: appBorder,
  );
}

class _RoleMixCell extends StatelessWidget {
  const _RoleMixCell({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: 24,
            height: 1,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 5),
        Text(label, style: appMono(fontSize: 9, letterSpacing: 1.2)),
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
