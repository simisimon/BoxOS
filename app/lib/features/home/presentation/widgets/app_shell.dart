import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/responsive/breakpoints.dart';
import 'package:app/features/home/presentation/widgets/shell_destinations.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';

const boxOsLogoAsset = 'assets/images/boxOS_logo.png';

class AuthenticatedScaffold extends StatelessWidget {
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
  final Widget body;

  /// Called with the branch index of the tapped destination.
  final ValueChanged<int> onSelectBranch;
  final VoidCallback onHeaderProfileTap;
  final VoidCallback onNotificationsTap;
  final ValueChanged<UserRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    final useRail = context.usesNavigationRail;
    return Scaffold(
      backgroundColor: appPageBackground,
      extendBodyBehindAppBar: false,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(MediaQuery.of(context).padding.top + 72),
        child: _ShellHeader(
          displayName: displayName,
          roleLabel: roleLabel,
          availableRoles: availableRoles,
          unreadNotifications: unreadNotifications,
          profileImageUrl: profileImageUrl,
          onProfileTap: onHeaderProfileTap,
          onNotificationsTap: onNotificationsTap,
          onRoleSelected: onRoleSelected,
          // Span the full bar next to the rail; clamp to the content column
          // when the bottom navigation is in use.
          maxWidth: useRail ? double.infinity : context.contentMaxWidth,
        ),
      ),
      body: DecoratedBox(
        decoration: appPageDecoration(),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (useRail)
                _ShellRail(
                  selectedBranchIndex: selectedBranchIndex,
                  destinations: destinations,
                  onSelectBranch: onSelectBranch,
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = context.contentMaxWidth;
                    final horizontalPadding = constraints.maxWidth > maxWidth
                        ? (constraints.maxWidth - maxWidth) / 2
                        : 0.0;
                    return Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: horizontalPadding),
                      child: body,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: useRail
          ? null
          : _ShellFooter(
              selectedBranchIndex: selectedBranchIndex,
              destinations: destinations,
              onSelectBranch: onSelectBranch,
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
                    _HeaderIconButton(
                      icon: Icons.swap_horiz_rounded,
                      tooltip: 'Switch role',
                      onTap: () async {
                        final renderBox =
                            context.findRenderObject() as RenderBox?;
                        final position = renderBox == null
                            ? const RelativeRect.fromLTRB(0, 0, 0, 0)
                            : RelativeRect.fromRect(
                                Rect.fromPoints(
                                  renderBox.localToGlobal(Offset.zero),
                                  renderBox.localToGlobal(
                                    renderBox.size.bottomRight(Offset.zero),
                                  ),
                                ),
                                Offset.zero & MediaQuery.of(context).size,
                              );
                        final selected = await showMenu<UserRole>(
                          context: context,
                          position: position,
                          items: availableRoles
                              .map(
                                (role) => PopupMenuItem<UserRole>(
                                  value: role,
                                  child: Text(role.label),
                                ),
                              )
                              .toList(),
                        );
                        if (selected != null) {
                          onRoleSelected(selected);
                        }
                      },
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

/// The wide-window counterpart to [_ShellFooter]: a side navigation rail shown
/// from the `expanded` breakpoint upwards (tablets in landscape, desktop).
class _ShellRail extends StatelessWidget {
  const _ShellRail({
    required this.selectedBranchIndex,
    required this.destinations,
    required this.onSelectBranch,
  });

  final int selectedBranchIndex;
  final List<ShellDestination> destinations;
  final ValueChanged<int> onSelectBranch;

  @override
  Widget build(BuildContext context) {
    // Map the active branch onto its position in this role's destination list;
    // fall back to the first tab when the active branch has no matching tab
    // (e.g. an athlete deep-linked into the programming branch).
    final selectedIndex = destinations.indexWhere(
      (d) => d.branchIndex == selectedBranchIndex,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: appPageBackground,
        border: Border(right: BorderSide(color: appBorder)),
      ),
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        onDestinationSelected: (index) =>
            onSelectBranch(destinations[index].branchIndex),
        labelType: NavigationRailLabelType.all,
        indicatorColor: appPrimarySoft,
        selectedIconTheme: const IconThemeData(color: appText),
        unselectedIconTheme: const IconThemeData(color: appSubtleText),
        selectedLabelTextStyle: const TextStyle(
          color: appText,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: appSubtleText,
          fontWeight: FontWeight.w600,
        ),
        destinations: [
          for (final dest in destinations)
            NavigationRailDestination(
              icon: Icon(dest.icon),
              selectedIcon: Icon(dest.activeIcon),
              label: Text(dest.label),
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
    required this.onSelectBranch,
  });

  final int selectedBranchIndex;
  final List<ShellDestination> destinations;
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
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
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
                      color: selected
                          ? appPrimaryHairline
                          : Colors.transparent,
                    ),
                  ),
                  child: Icon(
                    selected ? activeIcon : icon,
                    color: selected ? appPrimary : color,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
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
