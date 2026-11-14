import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/members/domain/member_booking.dart';
import 'package:app/features/members/presentation/widgets/booking_table.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';

/// Mutable draft surfaced to the parent on Save. The parent decides what to
/// persist and how — this widget is purely view/edit chrome.
class MemberDraft {
  MemberDraft({
    required this.user,
    required this.roles,
    required this.activeRole,
    required this.status,
    required this.adminNote,
  });

  final RoleManagedUser user;
  final Set<UserRole> roles;
  final UserRole activeRole;
  final MembershipStatus status;
  final String adminNote;
}

String memberDisplayName(RoleManagedUser user) {
  final name = user.displayName.trim();
  return name.isEmpty ? user.email : name;
}

AppPillIntent _rolePillIntent(UserRole role) => switch (role) {
  UserRole.admin || UserRole.trainer => AppPillIntent.primary,
  UserRole.athlete => AppPillIntent.neutral,
};

/// Members table (docs/admin-ui-reference.md §4.1): role filter chips, then
/// Name · Email · Role · Date joined, sortable by name and date. A row click
/// hands the member to [onOpen]; the detail is a page of its own.
class MemberRoster extends StatefulWidget {
  const MemberRoster({
    super.key,
    required this.users,
    required this.onOpen,
    this.query = '',
    this.onRefresh,
  });

  final List<RoleManagedUser> users;
  final ValueChanged<RoleManagedUser> onOpen;

  /// Search text from the page toolbar: matches name, nickname or email.
  final String query;

  /// Pull-to-refresh on the table; null disables it.
  final Future<void> Function()? onRefresh;

  @override
  State<MemberRoster> createState() => _MemberRosterState();
}

class _MemberRosterState extends State<MemberRoster> {
  UserRole? _roleFilter;

  /// Column index of [_columns] the table is sorted by.
  int _sortColumn = 0;
  bool _sortAscending = true;

  static const _columns = [
    AppTableColumn('Name', flex: 3, sortable: true),
    AppTableColumn('Email', flex: 3, hideWhenNarrow: true),
    AppTableColumn('Role', flex: 2),
    AppTableColumn(
      'Date joined',
      flex: 2,
      sortable: true,
      hideWhenNarrow: true,
    ),
  ];

  List<RoleManagedUser> _visibleUsers() {
    final query = widget.query.trim().toLowerCase();
    final filtered = widget.users.where((user) {
      if (_roleFilter != null && user.role != _roleFilter) return false;
      if (query.isEmpty) return true;
      return user.displayName.toLowerCase().contains(query) ||
          user.nickname.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query);
    }).toList();
    final dir = _sortAscending ? 1 : -1;
    filtered.sort((a, b) {
      if (_sortColumn == 3) {
        final aDate = a.joinedAt;
        final bDate = b.joinedAt;
        // Members without a date go last either way.
        if (aDate == null || bDate == null) {
          return aDate == bDate ? 0 : (aDate == null ? 1 : -1);
        }
        return aDate.compareTo(bDate) * dir;
      }
      return memberDisplayName(
            a,
          ).toLowerCase().compareTo(memberDisplayName(b).toLowerCase()) *
          dir;
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleUsers();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: appSpaceSm,
          runSpacing: appSpaceSm,
          children: [
            for (final role in const [
              null,
              UserRole.athlete,
              UserRole.trainer,
              UserRole.admin,
            ])
              _FilterChip(
                // Counts replace the old role-mix summary.
                label:
                    '${role?.label ?? 'All'} '
                    '${role == null ? widget.users.length : widget.users.where((u) => u.role == role).length}',
                selected: _roleFilter == role,
                onTap: () => setState(() => _roleFilter = role),
              ),
          ],
        ),
        const SizedBox(height: appSpaceMd),
        Expanded(
          child: _withRefresh(
            AppDataTable<RoleManagedUser>(
              columns: _columns,
              rows: visible,
              total: widget.users.length,
              sortColumn: _sortColumn,
              sortAscending: _sortAscending,
              onSort: (column) => setState(() {
                _sortAscending = column == _sortColumn ? !_sortAscending : true;
                _sortColumn = column;
              }),
              onRowTap: widget.onOpen,
              emptyText: 'No members match the current search or filter.',
              cells: (user) => [
                Row(
                  children: [
                    AppAvatar(
                      displayName: memberDisplayName(user),
                      imageUrl: user.profileImageUrl.isEmpty
                          ? null
                          : user.profileImageUrl,
                      size: 28,
                    ),
                    const SizedBox(width: appSpaceSm + 2),
                    Expanded(
                      child: Text(
                        memberDisplayName(user),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: appText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                _CellText(user.email),
                Wrap(
                  spacing: appSpaceXs,
                  runSpacing: appSpaceXs,
                  children: [
                    AppPill(
                      label: user.role.label,
                      intent: _rolePillIntent(user.role),
                      dense: true,
                    ),
                    ..._attentionPills(user),
                  ],
                ),
                _CellText(
                  user.joinedAt == null ? '—' : formatShortDate(user.joinedAt!),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _withRefresh(Widget table) => widget.onRefresh == null
      ? table
      : RefreshIndicator(onRefresh: widget.onRefresh!, child: table);
}

/// Status that needs the owner's eye: paused/removed, a plan request, or an
/// overdue payment.
List<Widget> _attentionPills(RoleManagedUser user) => [
  if (user.status != MembershipStatus.active)
    AppPill(
      label: user.status.label,
      intent: user.status == MembershipStatus.paused
          ? AppPillIntent.warning
          : AppPillIntent.danger,
      dense: true,
    ),
  if (user.hasPlanRequest)
    const AppPill(
      label: 'Plan request',
      intent: AppPillIntent.warning,
      dense: true,
    )
  else if (user.plan?.paymentStatus == PaymentStatus.overdue)
    const AppPill(label: 'Overdue', intent: AppPillIntent.danger, dense: true),
];

class _CellText extends StatelessWidget {
  const _CellText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: appMutedText, fontSize: 13),
  );
}

/// Member details page body (docs/admin-ui-reference.md §4.2): header card,
/// then tabs Overview | Memberships | Classes | Results. [planSection] is the
/// member's plan card, [membershipsTab] the full plan table, [bookings] feeds
/// Classes, [resultsTab] (when given) is the member's WOD results.
class MemberDetailView extends StatelessWidget {
  const MemberDetailView({
    super.key,
    required this.user,
    required this.saving,
    required this.onSave,
    required this.planSection,
    required this.membershipsTab,
    required this.bookings,
    this.resultsTab,
    this.onBack,
  });

  final RoleManagedUser user;
  final bool saving;
  final Future<void> Function(MemberDraft draft) onSave;
  final Widget planSection;
  final Widget membershipsTab;
  final Future<List<MemberBooking>> bookings;
  final Widget? resultsTab;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final resultsTab = this.resultsTab;
    return DefaultTabController(
      length: resultsTab == null ? 3 : 4,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: _MemberDetailHeader(user: user, onBack: onBack),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: appSpaceMd),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  const Tab(text: 'Overview'),
                  const Tab(text: 'Memberships'),
                  const Tab(text: 'Classes'),
                  if (resultsTab != null) const Tab(text: 'Results'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            _OverviewTab(
              user: user,
              saving: saving,
              onSave: onSave,
              planSection: planSection,
            ),
            membershipsTab,
            _ClassesTab(bookings: bookings),
            if (resultsTab != null)
              ListView(
                padding: const EdgeInsets.symmetric(vertical: appSpaceLg),
                children: [resultsTab],
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberDetailHeader extends StatelessWidget {
  const _MemberDetailHeader({required this.user, this.onBack});

  final RoleManagedUser user;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final name = memberDisplayName(user);
    final joined = user.joinedAt;
    return Container(
      padding: const EdgeInsets.all(appSpaceLg),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(appRadiusLg),
        border: Border.all(color: appBorder),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              tooltip: 'Back to members',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, color: appMutedText),
            ),
            const SizedBox(width: appSpaceSm),
          ],
          AppAvatar(
            displayName: name,
            imageUrl: user.profileImageUrl.isEmpty
                ? null
                : user.profileImageUrl,
            size: 52,
          ),
          const SizedBox(width: appSpaceLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: appSpaceSm,
                  runSpacing: appSpaceXs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: appText,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    AppPill(
                      label: user.role.label,
                      intent: _rolePillIntent(user.role),
                      dense: true,
                    ),
                    ..._attentionPills(user),
                  ],
                ),
                const SizedBox(height: appSpaceXs),
                Text(
                  [
                    user.email,
                    if (user.nickname.isNotEmpty) '@${user.nickname}',
                    if (joined != null) 'Joined ${formatShortDate(joined)}',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: appSubtleText, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Overview: plan card and KPIs on the left, profile and member settings on
/// the right; one column on narrow screens.
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.user,
    required this.saving,
    required this.onSave,
    required this.planSection,
  });

  final RoleManagedUser user;
  final bool saving;
  final Future<void> Function(MemberDraft draft) onSave;
  final Widget planSection;

  @override
  Widget build(BuildContext context) {
    final main = [
      _Card(child: planSection),
      const SizedBox(height: appSpaceLg),
      _MemberStats(user: user),
    ];
    final side = _Card(
      child: Padding(
        padding: const EdgeInsets.all(appSpaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _EditLabel('Profile'),
            const SizedBox(height: appSpaceSm),
            _MemberDetails(user: user),
            const SizedBox(height: appSpaceLg),
            const Divider(height: 1, color: appBorder),
            const SizedBox(height: appSpaceLg),
            _MemberEditForm(user: user, saving: saving, onSave: onSave),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(top: appSpaceLg, bottom: appSpace3xl),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: main,
                      ),
                    ),
                    const SizedBox(width: appSpaceLg),
                    SizedBox(width: 380, child: side),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...main,
                    const SizedBox(height: appSpaceLg),
                    side,
                  ],
                ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: appSurface,
      borderRadius: BorderRadius.circular(appRadiusLg),
      border: Border.all(color: appBorder),
    ),
    child: child,
  );
}

/// Classes tab: Upcoming | History, with attendance KPIs over the last 30
/// days above the table.
class _ClassesTab extends StatefulWidget {
  const _ClassesTab({required this.bookings});

  final Future<List<MemberBooking>> bookings;

  @override
  State<_ClassesTab> createState() => _ClassesTabState();
}

class _ClassesTabState extends State<_ClassesTab> {
  bool _history = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MemberBooking>>(
      future: widget.bookings,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const AppEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load classes',
            compact: true,
          );
        }
        if (!snapshot.hasData) return const AppLoadingState();
        final now = DateTime.now();
        final all = snapshot.data!;
        // Cancelled bookings go to History, even for future classes.
        final upcoming = [
          for (final b in all.reversed)
            if (b.end.isAfter(now) && !b.isCancelled) b,
        ];
        final history = [
          for (final b in all)
            if (!b.end.isAfter(now) || b.isCancelled) b,
        ];
        final monthAgo = now.subtract(const Duration(days: 30));
        final recent = history.where((b) => b.start.isAfter(monthAgo));
        final attended = recent.where((b) => b.status == 'attended').length;
        final noShows = recent.where((b) => b.status == 'no_show').length;
        final rows = _history ? history : upcoming;
        return Padding(
          padding: const EdgeInsets.only(top: appSpaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Attended (30 days)',
                      value: '$attended',
                      helper: 'classes checked in',
                    ),
                  ),
                  const SizedBox(width: appSpaceSm),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.event_busy_outlined,
                      label: 'No-shows (30 days)',
                      value: '$noShows',
                      helper: 'booked, not attended',
                    ),
                  ),
                  const SizedBox(width: appSpaceSm),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.trending_up_rounded,
                      label: 'Avg per week',
                      value: (attended * 7 / 30).toStringAsFixed(1),
                      helper: 'last 30 days',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: appSpaceLg),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text('Upcoming ${upcoming.length}'),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('History ${history.length}'),
                    ),
                  ],
                  selected: {_history},
                  onSelectionChanged: (s) => setState(() => _history = s.first),
                ),
              ),
              const SizedBox(height: appSpaceMd),
              Expanded(
                child: BookingTable(
                  rows: rows,
                  emptyText: _history
                      ? 'No past or cancelled classes yet.'
                      : 'No upcoming classes booked.',
                ),
              ),
              const SizedBox(height: appSpaceLg),
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? appPrimarySoft : appSurfaceAlt,
            borderRadius: BorderRadius.circular(appRadiusPill),
            border: Border.all(
              color: selected ? appPrimaryHairline : appBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? appPrimary : appText,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberEditForm extends StatefulWidget {
  const _MemberEditForm({
    required this.user,
    required this.saving,
    required this.onSave,
  });

  final RoleManagedUser user;
  final bool saving;
  final Future<void> Function(MemberDraft draft) onSave;

  @override
  State<_MemberEditForm> createState() => _MemberEditFormState();
}

class _MemberEditFormState extends State<_MemberEditForm> {
  late Set<UserRole> _roles;
  late UserRole _activeRole;
  late MembershipStatus _status;
  late TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _roles = {...user.availableRoles};
    _activeRole = user.role;
    _status = user.status;
    _noteController = TextEditingController(text: user.adminNote);
  }

  @override
  void didUpdateWidget(covariant _MemberEditForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync the draft only when the underlying user identity changes; the
    // server response updates the cached row, but the user's local edits in
    // progress should not be wiped if they're still looking at the same row.
    if (oldWidget.user.id != widget.user.id) {
      final user = widget.user;
      _roles = {...user.availableRoles};
      _activeRole = user.role;
      _status = user.status;
      _noteController.text = user.adminNote;
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canEdit => widget.user.canEditRole;

  bool get _dirty {
    final user = widget.user;
    if (_roles.length != user.availableRoles.length ||
        !_roles.containsAll(user.availableRoles)) {
      return true;
    }
    if (_activeRole != user.role) return true;
    if (_status != user.status) return true;
    if (_noteController.text != user.adminNote) return true;
    return false;
  }

  void _toggleRole(UserRole role, bool selected) {
    setState(() {
      if (selected) {
        _roles.add(role);
      } else {
        _roles.remove(role);
      }
      // Keep at least one assigned role; never POST an empty set.
      if (_roles.isEmpty) {
        _roles.add(UserRole.athlete);
      }
      if (!_roles.contains(_activeRole)) {
        _activeRole = _roles.first;
      }
    });
  }

  void _save() {
    widget.onSave(
      MemberDraft(
        user: widget.user,
        roles: {..._roles},
        activeRole: _activeRole,
        status: _status,
        adminNote: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEdit;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EditLabel('Assigned roles'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [UserRole.athlete, UserRole.trainer]
              .map(
                (role) => FilterChip(
                  label: Text(role.label),
                  selected: _roles.contains(role),
                  onSelected: canEdit && !widget.saving
                      ? (selected) => _toggleRole(role, selected)
                      : null,
                ),
              )
              .toList(),
        ),
        if (!canEdit) ...[
          const SizedBox(height: 8),
          Text(
            'Admin memberships are managed outside this screen.',
            style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
          ),
        ],
        if (canEdit && _roles.length > 1) ...[
          const SizedBox(height: appSpaceLg),
          const _EditLabel('Active role'),
          const SizedBox(height: 8),
          SegmentedButton<UserRole>(
            showSelectedIcon: false,
            segments: [
              for (final role in _roles)
                ButtonSegment<UserRole>(value: role, label: Text(role.label)),
            ],
            selected: {_activeRole},
            onSelectionChanged: widget.saving
                ? null
                : (selection) => setState(() => _activeRole = selection.first),
          ),
        ],
        if (canEdit) ...[
          const SizedBox(height: appSpaceLg),
          const _EditLabel('Membership status'),
          const SizedBox(height: 8),
          SegmentedButton<MembershipStatus>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: MembershipStatus.active,
                label: Text('Active'),
                icon: Icon(Icons.check_circle_outline_rounded, size: 16),
              ),
              ButtonSegment(
                value: MembershipStatus.paused,
                label: Text('Paused'),
                icon: Icon(Icons.pause_circle_outline_rounded, size: 16),
              ),
              ButtonSegment(
                value: MembershipStatus.removed,
                label: Text('Remove'),
                icon: Icon(Icons.person_remove_outlined, size: 16),
              ),
            ],
            selected: {_status},
            onSelectionChanged: widget.saving
                ? null
                : (selection) => setState(() => _status = selection.first),
          ),
          if (_status == MembershipStatus.removed) ...[
            const SizedBox(height: 8),
            Text(
              'Removing keeps the audit history but hides the member from the roster and blocks bookings.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: appDanger,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: appSpaceLg),
          const _EditLabel('Admin note'),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            enabled: !widget.saving,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText:
                  'Visible to admins and trainers only. Injuries, plan '
                  'expiry, anything worth remembering.',
            ),
          ),
        ],
        const SizedBox(height: appSpaceLg),
        Row(
          children: [
            const Spacer(),
            AppPrimaryButton(
              label: _status == MembershipStatus.removed
                  ? 'Remove member'
                  : 'Save changes',
              onPressed: canEdit && _dirty ? _save : null,
              busy: widget.saving,
              size: AppButtonSize.md,
              expand: false,
            ),
          ],
        ),
      ],
    );
  }
}

class _MemberStats extends StatelessWidget {
  const _MemberStats({required this.user});

  final RoleManagedUser user;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final tiles = [
          _StatTile(
            icon: Icons.percent_rounded,
            label: 'Booking rate',
            value: '${user.bookingRate.toStringAsFixed(1)}%',
            helper: '${user.attendedBookings} attended',
          ),
          _StatTile(
            icon: Icons.event_available_rounded,
            label: 'Total bookings',
            value: '${user.totalBookings}',
            helper: '${user.noShowBookings} no-shows',
          ),
        ];
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                tiles[i],
                if (i != tiles.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              Expanded(child: tiles[i]),
              if (i != tiles.length - 1) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
  });

  final IconData icon;
  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(appSpaceMd),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(appRadiusMd),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: appPrimary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appSubtleText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: appText,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            helper,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: appMutedText,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberDetails extends StatelessWidget {
  const _MemberDetails({required this.user});

  final RoleManagedUser user;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MetaRow(
          label: 'Email',
          value: user.email,
          icon: Icons.mail_outline_rounded,
        ),
        if (user.nickname.isNotEmpty) ...[
          const SizedBox(height: 6),
          _MetaRow(
            label: 'Nickname',
            value: '@${user.nickname}',
            icon: Icons.alternate_email_rounded,
          ),
        ],
        if (user.joinedAt != null) ...[
          const SizedBox(height: 6),
          _MetaRow(
            label: 'Contract start',
            value: formatShortDate(user.joinedAt!),
            icon: Icons.calendar_today_outlined,
          ),
        ],
        const SizedBox(height: 6),
        _MetaRow(
          label: 'Status',
          value: user.status.label,
          icon: Icons.verified_user_outlined,
        ),
        if (user.lastBookingAt != null) ...[
          const SizedBox(height: 6),
          _MetaRow(
            label: 'Last booking',
            value: formatShortDate(user.lastBookingAt!),
            icon: Icons.history_rounded,
          ),
        ],
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: appSubtleText),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(
            color: appSubtleText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: appText,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EditLabel extends StatelessWidget {
  const _EditLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: appSubtleText,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    );
  }
}

/// Short date as in the admin reference: `Nov 25, 26`.
String formatShortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final year = (local.year % 100).toString().padLeft(2, '0');
  return '${months[local.month - 1]} $day, $year';
}
