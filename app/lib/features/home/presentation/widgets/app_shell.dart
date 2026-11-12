import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/responsive/breakpoints.dart';
import 'package:app/features/home/presentation/widgets/shell_destinations.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';

const boxOsLogoAsset = 'assets/images/boxOS_logo.png';

class AuthenticatedScaffold extends StatefulWidget {
  const AuthenticatedScaffold({
    super.key,
    required this.selectedBranchIndex,
    required this.destinations,
    required this.displayName,
    required this.roleLabel,
    required this.availableRoles,
    required this.unreadNotifications,
    required this.body,
    required this.onSelectBranch,
    required this.onHeaderProfileTap,
    required this.onNotificationsTap,
    required this.onRoleSelected,
    this.profileImageUrl = '',
    this.email = '',
    this.gymName = '',
    this.gyms = const [],
    this.activeGymId,
    this.onGymSelected,
    this.onSignOut,
    this.fullBleedBody = false,
    this.branchBadges = const {},
  });

  /// The currently active shell branch (matches `navigationShell.currentIndex`).
  final int selectedBranchIndex;

  /// Role-specific nav destinations, in display order.
  final List<ShellDestination> destinations;

  final String displayName;
  final String roleLabel;
  final List<UserRole> availableRoles;
  final int unreadNotifications;
  final String profileImageUrl;
  final String email;

  /// Active gym shown in the sidebar's gym switcher, and the gyms it offers.
  final String gymName;
  final List<GymSummary> gyms;
  final int? activeGymId;
  final ValueChanged<int>? onGymSelected;
  final VoidCallback? onSignOut;
  final Widget body;

  /// Called with the branch index of the tapped destination.
  final ValueChanged<int> onSelectBranch;
  final VoidCallback onHeaderProfileTap;
  final VoidCallback onNotificationsTap;
  final ValueChanged<UserRole> onRoleSelected;

  /// When true the body fills the full width next to the sidebar instead of
  /// being clamped/centered to the readable content column. Views migrated to
  /// the admin layout are full width; the rest keep the column for now.
  final bool fullBleedBody;

  /// Counter badges per shell branch index, e.g. open join requests on
  /// Members. Missing or zero means no badge.
  final Map<int, int> branchBadges;

  @override
  State<AuthenticatedScaffold> createState() => _AuthenticatedScaffoldState();
}

class _AuthenticatedScaffoldState extends State<AuthenticatedScaffold> {
  /// The user's explicit choice; until then the sidebar starts collapsed
  /// below the `large` breakpoint so 840–1199px windows keep their content
  /// width.
  bool? _collapsedChoice;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final useSidebar = context.usesNavigationRail;
    final collapsed =
        _collapsedChoice ??
        !context.appBreakpoint.isAtLeast(AppBreakpoint.large);
    final body = w.fullBleedBody
        ? w.body
        : LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = context.contentMaxWidth;
              final horizontalPadding = constraints.maxWidth > maxWidth
                  ? (constraints.maxWidth - maxWidth) / 2
                  : 0.0;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: w.body,
              );
            },
          );

    if (useSidebar) {
      final active = w.destinations
          .where((d) => d.branchIndex == w.selectedBranchIndex)
          .firstOrNull;
      return Scaffold(
        backgroundColor: appPageBackground,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ShellSidebar(
              collapsed: collapsed,
              selectedBranchIndex: w.selectedBranchIndex,
              // Profile lives in the user card's menu on wide screens.
              destinations: [
                for (final d in w.destinations)
                  if (d.branchIndex != kProfileBranch) d,
              ],
              badges: w.branchBadges,
              onSelectBranch: w.onSelectBranch,
              gymName: w.gymName,
              roleLabel: w.roleLabel,
              gyms: w.gyms,
              activeGymId: w.activeGymId,
              onGymSelected: w.onGymSelected,
              unreadNotifications: w.unreadNotifications,
              onNotificationsTap: w.onNotificationsTap,
              displayName: w.displayName,
              email: w.email,
              profileImageUrl: w.profileImageUrl,
              availableRoles: w.availableRoles,
              onProfileTap: w.onHeaderProfileTap,
              onRoleSelected: w.onRoleSelected,
              onSignOut: w.onSignOut,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ShellTopBar(
                    title:
                        active?.label ??
                        (w.selectedBranchIndex == kProfileBranch
                            ? 'Profile'
                            : ''),
                    collapsed: collapsed,
                    onToggleSidebar: () =>
                        setState(() => _collapsedChoice = !collapsed),
                  ),
                  Expanded(child: AppGridBackground(child: body)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: appPageBackground,
      extendBodyBehindAppBar: false,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(MediaQuery.of(context).padding.top + 72),
        child: _ShellHeader(
          displayName: w.displayName,
          roleLabel: w.roleLabel,
          availableRoles: w.availableRoles,
          unreadNotifications: w.unreadNotifications,
          profileImageUrl: w.profileImageUrl,
          onProfileTap: w.onHeaderProfileTap,
          onNotificationsTap: w.onNotificationsTap,
          onRoleSelected: w.onRoleSelected,
          maxWidth: context.contentMaxWidth,
        ),
      ),
      body: AppGridBackground(
        child: SafeArea(top: false, bottom: false, child: body),
      ),
      bottomNavigationBar: _ShellFooter(
        selectedBranchIndex: w.selectedBranchIndex,
        destinations: w.destinations,
        badges: w.branchBadges,
        onSelectBranch: w.onSelectBranch,
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.displayName,
    required this.roleLabel,
    required this.availableRoles,
    required this.unreadNotifications,
    required this.profileImageUrl,
    required this.onProfileTap,
    required this.onNotificationsTap,
    required this.onRoleSelected,
    required this.maxWidth,
  });

  final String displayName;
  final String roleLabel;
  final List<UserRole> availableRoles;
  final int unreadNotifications;
  final String profileImageUrl;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationsTap;
  final ValueChanged<UserRole> onRoleSelected;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: appPageBackground,
            border: Border(bottom: BorderSide(color: appBorder)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  const _LogoBadge(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          displayName.isEmpty ? 'BoxOS' : displayName,
                          style: const TextStyle(
                            color: appText,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          roleLabel.toUpperCase(),
                          style: const TextStyle(
                            color: appSubtleText,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (availableRoles.length > 1) ...[
                    // Builder gives the button its own context, so the menu
                    // opens under the button instead of the header's corner.
                    Builder(
                      builder: (buttonContext) => _HeaderIconButton(
                        icon: Icons.swap_horiz_rounded,
                        tooltip: 'Switch role',
                        onTap: () async {
                          final selected = await _showRoleMenu(
                            buttonContext,
                            availableRoles,
                          );
                          if (selected != null) {
                            onRoleSelected(selected);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _HeaderIconButton(
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Notifications',
                    badge: unreadNotifications,
                    onTap: onNotificationsTap,
                  ),
                  const SizedBox(width: 6),
                  AppAvatar(
                    displayName: displayName,
                    imageUrl: profileImageUrl,
                    size: 40,
                    onTap: onProfileTap,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(appRadiusMd),
        color: appSurface,
        border: Border.all(color: appBorderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Image.asset(boxOsLogoAsset, fit: BoxFit.contain),
      ),
    );
  }
}

/// Opens the role menu right below the button that [buttonContext] belongs
/// to, positioned the same way [PopupMenuButton] does it.
Future<UserRole?> _showRoleMenu(
  BuildContext buttonContext,
  List<UserRole> roles,
) {
  final button = buttonContext.findRenderObject()! as RenderBox;
  final overlay =
      Overlay.of(buttonContext).context.findRenderObject()! as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(
        button.size.bottomLeft(Offset.zero) + const Offset(0, 6),
        ancestor: overlay,
      ),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero) + const Offset(0, 6),
        ancestor: overlay,
      ),
    ),
    Offset.zero & overlay.size,
  );
  return showMenu<UserRole>(
    context: buttonContext,
    position: position,
    items: [
      for (final role in roles)
        PopupMenuItem<UserRole>(value: role, child: Text(role.label)),
    ],
  );
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusMd),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: appSurface,
            borderRadius: BorderRadius.circular(appRadiusMd),
            border: Border.all(color: appBorder),
          ),
          child: Icon(icon, color: appText, size: 20),
        ),
      ),
    );

    return Tooltip(
      message: tooltip,
      child: badge > 0
          ? Badge(
              isLabelVisible: true,
              backgroundColor: appPrimary,
              textColor: Colors.white,
              label: Text(badge > 99 ? '99+' : '$badge'),
              child: button,
            )
          : button,
    );
  }
}

/// Opens a menu right below [anchorContext]'s widget, or right above it when
/// [above] is set (showMenu itself only ever opens downwards).
Future<T?> _showMenuBelow<T>(
  BuildContext anchorContext,
  List<PopupMenuEntry<T>> items, {
  bool above = false,
}) {
  final anchor = anchorContext.findRenderObject()! as RenderBox;
  final overlay =
      Overlay.of(anchorContext).context.findRenderObject()! as RenderBox;
  final topLeft = anchor.localToGlobal(
    above ? Offset.zero : anchor.size.bottomLeft(Offset.zero),
    ancestor: overlay,
  );
  // The menu adds 8px of vertical padding above and below its entries.
  final menuHeight = items.fold<double>(16, (sum, item) => sum + item.height);
  final rect = Rect.fromLTWH(
    topLeft.dx,
    above ? topLeft.dy - menuHeight : topLeft.dy,
    anchor.size.width,
    0,
  );
  return showMenu<T>(
    context: anchorContext,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    constraints: BoxConstraints(minWidth: anchor.size.width),
    color: appSurfaceElevated,
    items: items,
  );
}

const double _sidebarWidth = 248;
const double _sidebarCollapsedWidth = 72;

/// Left sidebar of the admin layout (docs/admin-ui-reference.md §0): gym
/// switcher, nav items, then Notifications and the user card at the bottom.
class _ShellSidebar extends StatelessWidget {
  const _ShellSidebar({
    required this.collapsed,
    required this.selectedBranchIndex,
    required this.destinations,
    required this.badges,
    required this.onSelectBranch,
    required this.gymName,
    required this.roleLabel,
    required this.gyms,
    required this.activeGymId,
    required this.onGymSelected,
    required this.unreadNotifications,
    required this.onNotificationsTap,
    required this.displayName,
    required this.email,
    required this.profileImageUrl,
    required this.availableRoles,
    required this.onProfileTap,
    required this.onRoleSelected,
    required this.onSignOut,
  });

  final bool collapsed;
  final int selectedBranchIndex;
  final List<ShellDestination> destinations;
  final Map<int, int> badges;
  final ValueChanged<int> onSelectBranch;
  final String gymName;
  final String roleLabel;
  final List<GymSummary> gyms;
  final int? activeGymId;
  final ValueChanged<int>? onGymSelected;
  final int unreadNotifications;
  final VoidCallback onNotificationsTap;
  final String displayName;
  final String email;
  final String profileImageUrl;
  final List<UserRole> availableRoles;
  final VoidCallback onProfileTap;
  final ValueChanged<UserRole> onRoleSelected;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final otherGyms = [
      for (final g in gyms)
        if (g.id != activeGymId) g,
    ];
    return Container(
      width: collapsed ? _sidebarCollapsedWidth : _sidebarWidth,
      decoration: const BoxDecoration(
        color: appPageBackgroundSoft,
        border: Border(right: BorderSide(color: appBorder)),
      ),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: appSpaceMd,
            vertical: appSpaceMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Builder(
                builder: (anchor) => _SidebarTile(
                  collapsed: collapsed,
                  leading: AppAvatar(
                    displayName: gymName.isEmpty ? 'BoxOS' : gymName,
                    size: 32,
                  ),
                  title: gymName.isEmpty ? 'BoxOS' : gymName,
                  subtitle: roleLabel,
                  tooltip: 'Switch gym',
                  trailing: otherGyms.isEmpty || onGymSelected == null
                      ? null
                      : const Icon(
                          Icons.unfold_more_rounded,
                          size: 18,
                          color: appSubtleText,
                        ),
                  onTap: otherGyms.isEmpty || onGymSelected == null
                      ? null
                      : () async {
                          final id = await _showMenuBelow<int>(anchor, [
                            for (final g in otherGyms)
                              PopupMenuItem(value: g.id, child: Text(g.name)),
                          ]);
                          if (id != null) onGymSelected!(id);
                        },
                ),
              ),
              const SizedBox(height: appSpaceLg),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final dest in destinations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _SidebarNavItem(
                          collapsed: collapsed,
                          icon: dest.branchIndex == selectedBranchIndex
                              ? dest.activeIcon
                              : dest.icon,
                          label: dest.label,
                          badge: badges[dest.branchIndex] ?? 0,
                          selected: dest.branchIndex == selectedBranchIndex,
                          onTap: () => onSelectBranch(dest.branchIndex),
                        ),
                      ),
                  ],
                ),
              ),
              _SidebarNavItem(
                collapsed: collapsed,
                icon: Icons.notifications_none_rounded,
                label: 'Notifications',
                badge: unreadNotifications,
                selected: false,
                onTap: onNotificationsTap,
              ),
              const Divider(height: appSpaceLg, color: appBorder),
              Builder(
                builder: (anchor) => _SidebarTile(
                  collapsed: collapsed,
                  leading: AppAvatar(
                    displayName: displayName,
                    imageUrl: profileImageUrl,
                    size: 32,
                  ),
                  title: displayName.isEmpty ? 'Account' : displayName,
                  subtitle: email,
                  tooltip: 'Account',
                  trailing: const Icon(
                    Icons.unfold_more_rounded,
                    size: 18,
                    color: appSubtleText,
                  ),
                  onTap: () async {
                    final action = await _showMenuBelow<Object>(anchor, [
                      const PopupMenuItem(
                        value: 'profile',
                        child: Text('Profile'),
                      ),
                      if (availableRoles.length > 1) ...[
                        const PopupMenuDivider(),
                        for (final role in availableRoles)
                          if (role.label != roleLabel)
                            PopupMenuItem(
                              value: role,
                              child: Text('Switch to ${role.label}'),
                            ),
                      ],
                      if (onSignOut != null) ...[
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'sign-out',
                          child: Text('Sign out'),
                        ),
                      ],
                    ], above: true);
                    switch (action) {
                      case 'profile':
                        onProfileTap();
                      case 'sign-out':
                        onSignOut?.call();
                      case UserRole role:
                        onRoleSelected(role);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gym switcher / user card row: leading avatar, two text lines, chevron.
class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.collapsed,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.tooltip,
    required this.onTap,
    this.trailing,
  });

  final bool collapsed;
  final Widget leading;
  final String title;
  final String subtitle;
  final String tooltip;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final content = collapsed
        ? Center(child: leading)
        : Row(
            children: [
              leading,
              const SizedBox(width: appSpaceSm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: appText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: appSubtleText,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          );
    return Tooltip(
      message: collapsed ? title : tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(appRadiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: appSpaceSm,
              vertical: appSpaceSm,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.collapsed,
    required this.icon,
    required this.label,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final bool collapsed;
  final IconData icon;
  final String label;
  final int badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? appText : appMutedText;
    final iconWidget = Icon(
      icon,
      size: 20,
      color: selected ? appPrimary : appSubtleText,
    );
    return Tooltip(
      message: collapsed ? label : '',
      child: Material(
        color: selected ? appSurfaceAlt : Colors.transparent,
        borderRadius: BorderRadius.circular(appRadiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(appRadiusMd),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: collapsed
                ? Center(
                    child: _CountBadge(count: badge, child: iconWidget),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: appSpaceSm + 2,
                    ),
                    child: Row(
                      children: [
                        iconWidget,
                        const SizedBox(width: appSpaceMd),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color,
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (badge > 0)
                          AppPill(
                            label: badge > 99 ? '99+' : '$badge',
                            intent: AppPillIntent.warning,
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Per-page top bar: collapse-sidebar button and the page title.
class _ShellTopBar extends StatelessWidget {
  const _ShellTopBar({
    required this.title,
    required this.collapsed,
    required this.onToggleSidebar,
  });

  final String title;
  final bool collapsed;
  final VoidCallback onToggleSidebar;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: appSpaceLg),
      decoration: const BoxDecoration(
        color: appPageBackground,
        border: Border(bottom: BorderSide(color: appBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
            onPressed: onToggleSidebar,
            icon: const Icon(
              Icons.view_sidebar_outlined,
              size: 20,
              color: appSubtleText,
            ),
          ),
          const SizedBox(width: appSpaceSm),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: appText,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellFooter extends StatelessWidget {
  const _ShellFooter({
    required this.selectedBranchIndex,
    required this.destinations,
    required this.badges,
    required this.onSelectBranch,
  });

  final int selectedBranchIndex;
  final List<ShellDestination> destinations;
  final Map<int, int> badges;
  final ValueChanged<int> onSelectBranch;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: appPageBackground,
            border: Border(top: BorderSide(color: appBorder)),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  for (final dest in destinations)
                    _FooterDest(
                      icon: dest.icon,
                      activeIcon: dest.activeIcon,
                      label: dest.label,
                      badge: badges[dest.branchIndex] ?? 0,
                      selected: dest.branchIndex == selectedBranchIndex,
                      onTap: () => onSelectBranch(dest.branchIndex),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterDest extends StatelessWidget {
  const _FooterDest({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? appText : appSubtleText;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(appRadiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? appPrimarySoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(appRadiusPill),
                    border: Border.all(
                      color: selected ? appPrimaryHairline : Colors.transparent,
                    ),
                  ),
                  child: _CountBadge(
                    count: badge,
                    child: Icon(
                      selected ? activeIcon : icon,
                      color: selected ? appPrimary : color,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  // The owner set has seven tabs; let longer labels wrap instead of
                  // overflowing on phones.
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Red counter on a tab icon, like unread mail on a phone home screen.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: appDanger,
      textColor: Colors.white,
      label: Text(count > 99 ? '99+' : '$count'),
      child: child,
    );
  }
}
