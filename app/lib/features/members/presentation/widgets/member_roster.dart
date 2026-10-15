import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
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

/// Sort options exposed in the table header.
enum _MemberSort {
  joinedNewest,
  joinedOldest,
  nameAsc;

  String get label {
    switch (this) {
      case _MemberSort.joinedNewest:
        return 'Newest first';
      case _MemberSort.joinedOldest:
        return 'Oldest first';
      case _MemberSort.nameAsc:
        return 'A → Z';
    }
  }
}

typedef _RoleFilter = UserRole?;

/// Members table with search, role filter, sort menu, and inline-expand rows
/// for full editing. Pure view widget: the parent provides the users list and
/// receives a [MemberDraft] on every save.
class MemberRoster extends StatefulWidget {
  const MemberRoster({
    super.key,
    required this.users,
    required this.onSave,
    this.savingUserId,
  });

  final List<RoleManagedUser> users;

  /// Persist the draft. The parent is responsible for showing snackbars and
  /// updating its source-of-truth list afterwards. Must return when the save
  /// resolves so the widget can clear its in-flight indicator.
  final Future<void> Function(MemberDraft draft) onSave;

  /// Optional external override of the spinning row — useful when the parent
  /// owns the in-flight state for snackbars / refresh side effects.
  final int? savingUserId;

  @override
  State<MemberRoster> createState() => _MemberRosterState();
}

class _MemberRosterState extends State<MemberRoster> {
  int? _internalSavingUserId;
  int? _selectedUserId;
  String _query = '';
  _RoleFilter _roleFilter;
  _MemberSort _sort = _MemberSort.joinedNewest;
  late final TextEditingController _searchController;

  _MemberRosterState() : _roleFilter = null;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int? get _effectiveSavingId => widget.savingUserId ?? _internalSavingUserId;

  List<RoleManagedUser> _visibleUsers() {
    final users = widget.users;
    final query = _query.trim().toLowerCase();
    final filtered = users.where((user) {
      if (_roleFilter != null && user.role != _roleFilter) return false;
      if (query.isEmpty) return true;
      return user.displayName.toLowerCase().contains(query) ||
          user.nickname.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query);
    }).toList();
    int joinedDir(_MemberSort sort) =>
        sort == _MemberSort.joinedNewest ? -1 : 1;
    filtered.sort((a, b) {
      switch (_sort) {
        case _MemberSort.joinedNewest:
        case _MemberSort.joinedOldest:
          final aDate = a.joinedAt;
          final bDate = b.joinedAt;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return aDate.compareTo(bDate) * joinedDir(_sort);
        case _MemberSort.nameAsc:
          return _displayKey(a).compareTo(_displayKey(b));
      }
    });
    return filtered;
  }

  static String _displayKey(RoleManagedUser user) {
    final name = user.displayName.trim();
    return (name.isEmpty ? user.email : name).toLowerCase();
  }

  Future<void> _save(MemberDraft draft) async {
    setState(() => _internalSavingUserId = draft.user.id);
    try {
      await widget.onSave(draft);
    } finally {
      if (mounted) setState(() => _internalSavingUserId = null);
    }
  }

  RoleManagedUser? _selectedUser(List<RoleManagedUser> visible) {
    if (visible.isEmpty) return null;
    for (final user in visible) {
      if (user.id == _selectedUserId) return user;
    }
    return visible.first;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleUsers();
    final selectedUser = _selectedUser(visible);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MemberToolbar(
          total: widget.users.length,
          visible: visible.length,
          searchController: _searchController,
          query: _query,
          onQueryChanged: (value) => setState(() => _query = value),
          roleFilter: _roleFilter,
          onRoleFilterChanged: (filter) => setState(() => _roleFilter = filter),
          sort: _sort,
          onSortChanged: (sort) => setState(() => _sort = sort),
        ),
        const SizedBox(height: appSpaceMd),
        if (visible.isEmpty)
          AppEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches',
            subtitle: 'No members match the current search or filter.',
            compact: true,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 860;
              final list = _MemberList(
                users: visible,
                selectedUserId: selectedUser?.id,
                savingUserId: _effectiveSavingId,
                onSelected: (user) => setState(() => _selectedUserId = user.id),
              );
              final detail = selectedUser == null
                  ? const SizedBox.shrink()
                  : _MemberDetailPanel(
                      user: selectedUser,
                      saving: _effectiveSavingId == selectedUser.id,
                      onSave: _save,
                    );
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    list,
                    const SizedBox(height: appSpaceMd),
                    detail,
                  ],
                );
              }
              final detailWidth = (constraints.maxWidth * 0.36)
                  .clamp(420.0, 520.0)
                  .toDouble();
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: list),
                  const SizedBox(width: appSpaceMd),
                  SizedBox(width: detailWidth, child: detail),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _MemberToolbar extends StatelessWidget {
  const _MemberToolbar({
    required this.total,
    required this.visible,
    required this.searchController,
    required this.query,
    required this.onQueryChanged,
    required this.roleFilter,
    required this.onRoleFilterChanged,
    required this.sort,
    required this.onSortChanged,
  });

  final int total;
  final int visible;
  final TextEditingController searchController;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final _RoleFilter roleFilter;
  final ValueChanged<_RoleFilter> onRoleFilterChanged;
  final _MemberSort sort;
  final ValueChanged<_MemberSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: searchController,
          onChanged: onQueryChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: 'Search by name, nickname, or email',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      searchController.clear();
                      onQueryChanged('');
                    },
                  ),
          ),
        ),
        const SizedBox(height: appSpaceMd),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'All',
                      selected: roleFilter == null,
                      onTap: () => onRoleFilterChanged(null),
                    ),
                    const SizedBox(width: 6),
                    for (final role in const [
                      UserRole.athlete,
                      UserRole.trainer,
                      UserRole.admin,
                    ]) ...[
                      _FilterChip(
                        label: role.label,
                        selected: roleFilter == role,
                        onTap: () => onRoleFilterChanged(role),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: appSpaceSm),
            _SortMenu(sort: sort, onChanged: onSortChanged),
          ],
        ),
        const SizedBox(height: appSpaceSm),
        Text(
          '$visible of $total members',
          style: const TextStyle(
            color: appSubtleText,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ],
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

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.sort, required this.onChanged});

  final _MemberSort sort;
  final ValueChanged<_MemberSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MemberSort>(
      tooltip: 'Sort',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in _MemberSort.values)
          PopupMenuItem<_MemberSort>(
            value: option,
            child: Row(
              children: [
                Icon(
                  option == sort
                      ? Icons.check_rounded
                      : Icons.swap_vert_rounded,
                  size: 16,
                  color: option == sort ? appPrimary : appSubtleText,
                ),
                const SizedBox(width: 8),
                Text(option.label),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: appSurfaceAlt,
          borderRadius: BorderRadius.circular(appRadiusMd),
          border: Border.all(color: appBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 16, color: appMutedText),
            const SizedBox(width: 6),
            Text(
              sort.label,
              style: const TextStyle(
                color: appText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 16,
              color: appMutedText,
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberList extends StatelessWidget {
  const _MemberList({
    required this.users,
    required this.selectedUserId,
    required this.savingUserId,
    required this.onSelected,
  });

  final List<RoleManagedUser> users;
  final int? selectedUserId;
  final int? savingUserId;
  final ValueChanged<RoleManagedUser> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100 ? 3 : (width >= 680 ? 2 : 1);
        final spacing = appSpaceSm;
        final itemWidth = columns <= 1
            ? width
            : (width - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final user in users)
              SizedBox(
                width: itemWidth,
                child: _MemberRow(
                  key: ValueKey(user.id),
                  user: user,
                  selected: user.id == selectedUserId,
                  saving: savingUserId == user.id,
                  onSelected: () => onSelected(user),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    super.key,
    required this.user,
    required this.selected,
    required this.saving,
    required this.onSelected,
  });

  final RoleManagedUser user;
  final bool selected;
  final bool saving;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusLg),
        onTap: onSelected,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? appSurfaceElevated : appSurface,
            borderRadius: BorderRadius.circular(appRadiusLg),
            border: Border.all(
              color: selected ? appPrimaryHairline : appBorder,
            ),
          ),
          child: _MemberHeader(
            user: user,
            selected: selected,
            saving: saving,
            onSelected: onSelected,
          ),
        ),
      ),
    );
  }
}

class _MemberHeader extends StatelessWidget {
  const _MemberHeader({
    required this.user,
    required this.selected,
    required this.saving,
    required this.onSelected,
  });

  final RoleManagedUser user;
  final bool selected;
  final bool saving;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final name = displayName(user);
    final secondary = secondaryLine(user);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        appSpaceMd,
        appSpaceMd,
        appSpaceMd,
        appSpaceMd,
      ),
      child: Row(
        children: [
          AppAvatar(
            displayName: name,
            imageUrl: user.profileImageUrl.isEmpty
                ? null
                : user.profileImageUrl,
            size: 40,
          ),
          const SizedBox(width: appSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appText,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                if (secondary != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: appSubtleText, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: appSpaceSm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppPill(
                label: user.role.label,
                intent: rolePillIntent(user.role),
                dense: true,
              ),
              if (user.status != MembershipStatus.active) ...[
                const SizedBox(height: 4),
                AppPill(
                  label: user.status.label,
                  intent: user.status == MembershipStatus.paused
                      ? AppPillIntent.warning
                      : AppPillIntent.danger,
                  dense: true,
                ),
              ],
            ],
          ),
          const SizedBox(width: 4),
          if (saving)
            const SizedBox(
              width: 36,
              height: 36,
              child: Padding(
                padding: EdgeInsets.all(9),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Select member',
              visualDensity: VisualDensity.compact,
              onPressed: onSelected,
              icon: Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected ? appPrimary : appSubtleText,
                size: 22,
              ),
            ),
        ],
      ),
    );
  }

  static String displayName(RoleManagedUser user) {
    final name = user.displayName.trim();
    return name.isEmpty ? user.email : name;
  }

  static String? secondaryLine(RoleManagedUser user) {
    final parts = <String>[];
    if (user.joinedAt != null) {
      parts.add('Joined ${_formatDate(user.joinedAt!)}');
    }
    if (user.nickname.isNotEmpty) parts.add('@${user.nickname}');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static AppPillIntent rolePillIntent(UserRole role) {
    switch (role) {
      case UserRole.admin:
      case UserRole.trainer:
        return AppPillIntent.primary;
      case UserRole.athlete:
        return AppPillIntent.neutral;
    }
  }
}

class _MemberDetailPanel extends StatelessWidget {
  const _MemberDetailPanel({
    required this.user,
    required this.saving,
    required this.onSave,
  });

  final RoleManagedUser user;
  final bool saving;
  final Future<void> Function(MemberDraft draft) onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(appRadiusLg),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MemberDetailHeader(user: user),
          _MemberRowExpanded(user: user, saving: saving, onSave: onSave),
        ],
      ),
    );
  }
}

class _MemberDetailHeader extends StatelessWidget {
  const _MemberDetailHeader({required this.user});

  final RoleManagedUser user;

  @override
  Widget build(BuildContext context) {
    final name = _MemberHeader.displayName(user);
    final secondary = _MemberHeader.secondaryLine(user);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        appSpaceLg,
        appSpaceLg,
        appSpaceMd,
        appSpaceMd,
      ),
      child: Row(
        children: [
          AppAvatar(
            displayName: name,
            imageUrl: user.profileImageUrl.isEmpty
                ? null
                : user.profileImageUrl,
            size: 44,
          ),
          const SizedBox(width: appSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appText,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                if (secondary != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    secondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: appSubtleText,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRowExpanded extends StatefulWidget {
  const _MemberRowExpanded({
    required this.user,
    required this.saving,
    required this.onSave,
  });

  final RoleManagedUser user;
  final bool saving;
  final Future<void> Function(MemberDraft draft) onSave;

  @override
  State<_MemberRowExpanded> createState() => _MemberRowExpandedState();
}

class _MemberRowExpandedState extends State<_MemberRowExpanded> {
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
  void didUpdateWidget(covariant _MemberRowExpanded oldWidget) {
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
    final user = widget.user;
    final canEdit = _canEdit;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(appSpaceLg, 0, appSpaceLg, appSpaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: appBorder),
          const SizedBox(height: appSpaceMd),
          _MemberStats(user: user),
          const SizedBox(height: appSpaceLg),
          const _EditLabel('Member details'),
          const SizedBox(height: 8),
          _MemberDetails(user: user),
          const SizedBox(height: appSpaceLg),
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
                  : (selection) =>
                        setState(() => _activeRole = selection.first),
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
      ),
    );
  }
}

class _MemberStats extends StatelessWidget {
  const _MemberStats({required this.user});

  final RoleManagedUser user;

  @override
  Widget build(BuildContext context) {
    final newestPr = user.newestPrTitle.trim().isEmpty
        ? 'No PR yet'
        : '${user.newestPrTitle} · ${user.newestPrScore}';
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
          _StatTile(
            icon: Icons.emoji_events_outlined,
            label: 'Newest PR',
            value: newestPr,
            helper: user.newestPrAt == null
                ? 'No logged PR'
                : _formatDate(user.newestPrAt!),
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
            value: _formatDate(user.joinedAt!),
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
            value: _formatDate(user.lastBookingAt!),
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

String _formatDate(DateTime date) {
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
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
