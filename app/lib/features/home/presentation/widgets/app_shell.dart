import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';

const boxOsLogoAsset = 'assets/images/boxOS_logo.png';

class AuthenticatedScaffold extends StatelessWidget {
  const AuthenticatedScaffold({
    super.key,
    required this.selectedIndex,
    required this.displayName,
    required this.roleLabel,
    required this.availableRoles,
    required this.unreadNotifications,
    required this.body,
    required this.onHomeTap,
    required this.onMyBoxTap,
    required this.onLogbookTap,
    required this.onProfileTap,
    required this.onHeaderProfileTap,
    required this.onNotificationsTap,
    required this.onRoleSelected,
  });

  final int selectedIndex;
  final String displayName;
  final String roleLabel;
  final List<UserRole> availableRoles;
  final int unreadNotifications;
  final Widget body;
  final VoidCallback onHomeTap;
  final VoidCallback onMyBoxTap;
  final VoidCallback onLogbookTap;
  final VoidCallback onProfileTap;
  final VoidCallback onHeaderProfileTap;
  final VoidCallback onNotificationsTap;
  final ValueChanged<UserRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
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
          onProfileTap: onHeaderProfileTap,
          onNotificationsTap: onNotificationsTap,
          onRoleSelected: onRoleSelected,
        ),
      ),
      body: DecoratedBox(
        decoration: appPageDecoration(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding =
                constraints.maxWidth > mobileContentMaxWidth
                    ? (constraints.maxWidth - mobileContentMaxWidth) / 2
                    : 0.0;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: body,
            );
          },
        ),
      ),
      bottomNavigationBar: _ShellFooter(
        selectedIndex: selectedIndex,
        onHomeTap: onHomeTap,
        onMyBoxTap: onMyBoxTap,
        onLogbookTap: onLogbookTap,
        onProfileTap: onProfileTap,
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
    required this.onProfileTap,
    required this.onNotificationsTap,
    required this.onRoleSelected,
  });

  final String displayName;
  final String roleLabel;
  final List<UserRole> availableRoles;
  final int unreadNotifications;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationsTap;
  final ValueChanged<UserRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: mobileContentMaxWidth),
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
                  _AvatarButton(
                    displayName: displayName,
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

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.displayName, required this.onTap});

  final String displayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: appPrimarySoft,
          borderRadius: BorderRadius.circular(appRadiusPill),
          border: Border.all(color: appPrimaryHairline),
        ),
        child: Text(
          _initials(displayName),
          style: const TextStyle(
            color: appText,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  static String _initials(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'U';
    }
    final parts = normalized.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _ShellFooter extends StatelessWidget {
  const _ShellFooter({
    required this.selectedIndex,
    required this.onHomeTap,
    required this.onMyBoxTap,
    required this.onLogbookTap,
    required this.onProfileTap,
  });

  final int selectedIndex;
  final VoidCallback onHomeTap;
  final VoidCallback onMyBoxTap;
  final VoidCallback onLogbookTap;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: mobileContentMaxWidth),
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
                  _FooterDest(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: 'Home',
                    selected: selectedIndex == 0,
                    onTap: onHomeTap,
                  ),
                  _FooterDest(
                    icon: Icons.fitness_center_outlined,
                    activeIcon: Icons.fitness_center_rounded,
                    label: 'My Box',
                    selected: selectedIndex == 1,
                    onTap: onMyBoxTap,
                  ),
                  _FooterDest(
                    icon: Icons.menu_book_outlined,
                    activeIcon: Icons.menu_book_rounded,
                    label: 'Logbook',
                    selected: selectedIndex == 2,
                    onTap: onLogbookTap,
                  ),
                  _FooterDest(
                    icon: Icons.person_outline_rounded,
                    activeIcon: Icons.person_rounded,
                    label: 'Profile',
                    selected: selectedIndex == 3,
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
