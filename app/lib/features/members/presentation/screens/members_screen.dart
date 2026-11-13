import 'dart:async';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/responsive/responsive_masonry.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/gyms/domain/models/gym_join_request.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:app/features/memberships/presentation/member_plan_widgets.dart';
import 'package:app/features/members/presentation/widgets/member_roster.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Owner-facing "Members" page (docs/admin-ui-reference.md §4.1): a Members |
/// Requests segment with the search on the right, the roster as a table whose
/// rows open the member's own page, and join and plan requests.
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
  List<MemberPlan> _planRequests = const [];
  List<RoleManagedUser> _users = const [];

  int? _pendingRequestId;
  int? _pendingPlanRequestId;

  /// Members and join requests share the page as two tabs.
  bool _showRequests = false;
  String _query = '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final gymRepo = ref.read(gymRepositoryProvider);
      final profileRepo = ref.read(profileRepositoryProvider);
      final membershipRepo = ref.read(membershipRepositoryProvider);
      final results = await Future.wait<Object>([
        gymRepo.fetchJoinRequests(),
        profileRepo.fetchRoleManagedUsers(),
        // Plan requests are an addition to the page; never block it on them.
        membershipRepo.fetchPlanRequests().catchError(
          (Object _) => const <MemberPlan>[],
        ),
      ]);
      if (!mounted) return;
      // Keep the Members tab badge in step with what this screen shows.
      ref.invalidate(pendingJoinRequestsProvider);
      ref.invalidate(pendingPlanRequestsProvider);
      setState(() {
        _requests = results[0] as List<GymJoinRequest>;
        _users = results[1] as List<RoleManagedUser>;
        _planRequests = results[2] as List<MemberPlan>;
        _loaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = errorMessageFrom(
          error,
          fallback: 'Failed to load members',
        );
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
            approve
                ? 'Approved ${request.email}.'
                : 'Rejected ${request.email}.',
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

  Future<void> _reviewPlanRequest(MemberPlan request, bool approve) async {
    setState(() => _pendingPlanRequestId = request.id);
    final handled = await reviewPlanRequest(
      context,
      ref,
      request,
      approve: approve,
    );
    if (!mounted) return;
    setState(() {
      _pendingPlanRequestId = null;
      if (handled) {
        _planRequests = [
          for (final r in _planRequests)
            if (r.id != request.id) r,
        ];
      }
    });
    if (handled) unawaited(_reloadRoster());
  }

  Future<void> _reloadPlanRequests() async {
    try {
      final requests = await ref
          .read(membershipRepositoryProvider)
          .fetchPlanRequests();
      if (!mounted) return;
      ref.invalidate(pendingPlanRequestsProvider);
      setState(() => _planRequests = requests);
    } catch (_) {
      // Non-fatal: keep the previous list.
    }
  }

  Future<void> _reloadRoster() async {
    try {
      final users = await ref
          .read(profileRepositoryProvider)
          .fetchRoleManagedUsers();
      if (!mounted) return;
      setState(() => _users = users);
    } catch (_) {
      // Non-fatal: the roster simply keeps its previous state.
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

    return AppGridBackground(child: _buildBody(profileAsync, hasAccess));
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
          Wrap(
            // One line on wide screens, search below the segment on phones.
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: appSpaceMd,
            runSpacing: appSpaceSm,
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.group_outlined),
                    label: Text('Members ${_users.length}'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: Text(
                      'Requests ${_requests.length + _planRequests.length}',
                    ),
                  ),
                ],
                selected: {_showRequests},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _showRequests = selection.first),
              ),
              if (!_showRequests)
                SizedBox(
                  width: 260,
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Search member',
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                    ),
                  ),
                ),
            ],
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
    return MemberRoster(
      users: _users,
      query: _query,
      onRefresh: _refresh,
      onOpen: (user) async {
        await context.push('/members/${user.id}');
        // The detail page may have changed roles, status or the plan.
        if (!mounted) return;
        unawaited(_reloadRoster());
        unawaited(_reloadPlanRequests());
      },
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
    if (_requests.isEmpty && _planRequests.isEmpty) {
      return AppEmptyState(
        icon: Icons.inbox_outlined,
        title: 'No pending requests',
        subtitle:
            'New athletes asking to join your box and members asking for a '
            'plan appear here.',
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
        for (final request in _planRequests)
          PlanRequestCard(
            request: request,
            isPending: _pendingPlanRequestId == request.id,
            onApprove: () => _reviewPlanRequest(request, true),
            onReject: () => _reviewPlanRequest(request, false),
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
    final displayName = request.displayName.isEmpty
        ? request.email
        : request.displayName;
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
                    if (request.requestedPlanName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Wants ${request.requestedPlanName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: appPrimary,
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
