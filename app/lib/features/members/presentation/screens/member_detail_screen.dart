import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/members/domain/member_booking.dart';
import 'package:app/features/members/presentation/widgets/member_roster.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/memberships/presentation/member_plan_widgets.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Member details page (docs/admin-ui-reference.md §4.2), opened from a row
/// of the Members table at `/members/:userId`.
class MemberDetailScreen extends ConsumerStatefulWidget {
  const MemberDetailScreen({super.key, required this.userId});

  final int userId;

  @override
  ConsumerState<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  RoleManagedUser? _user;
  String? _error;
  bool _saving = false;
  late final Future<List<MemberBooking>> _bookings = ref
      .read(membershipRepositoryProvider)
      .fetchMemberBookings(widget.userId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  // shortcut: reads the whole roster to find one member; add a single-member
  // endpoint if rosters get large.
  Future<void> _load() async {
    try {
      final users = await ref
          .read(profileRepositoryProvider)
          .fetchRoleManagedUsers();
      if (!mounted) return;
      final user = users.where((u) => u.id == widget.userId).firstOrNull;
      setState(() {
        _user = user;
        _error = user == null ? 'This member is no longer in your box.' : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _error = errorMessageFrom(error, fallback: 'Failed to load member'),
      );
    }
  }

  void _back() => context.canPop() ? context.pop() : context.go('/members');

  Future<void> _save(MemberDraft draft) async {
    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(profileRepositoryProvider)
          .updateUserRole(
            userId: draft.user.id,
            roles: draft.roles.toList(),
            activeRole: draft.activeRole,
            status: draft.status,
            adminNote: draft.adminNote,
          );
      ref.invalidate(currentProfileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved ${updated.email}.')));
      if (updated.status == MembershipStatus.removed) {
        _back();
        return;
      }
      setState(() => _user = updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to update member'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return AppGridBackground(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          appSpaceLg,
          appSpaceLg,
          appSpaceLg,
          0,
        ),
        child: user != null
            ? MemberDetailView(
                user: user,
                saving: _saving,
                onSave: _save,
                onBack: _back,
                bookings: _bookings,
                planSection: MemberPlanSection(
                  userId: user.id,
                  memberName: memberDisplayName(user),
                  onChanged: _load,
                ),
                membershipsTab: MemberPlanSection(
                  userId: user.id,
                  memberName: memberDisplayName(user),
                  onChanged: _load,
                  asTable: true,
                ),
              )
            : _error != null
            ? AppEmptyState.error(
                title: 'Could not open member',
                subtitle: _error,
                actionLabel: 'Back to members',
                onAction: _back,
              )
            : const AppLoadingState(),
      ),
    );
  }
}
