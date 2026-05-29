import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';

const boxOsLogoAsset = 'assets/images/boxOS_logo.png';
const _shellBlue = appPrimary;
const _shellBackground = appPageBackground;
const _shellSurface = appSurface;
const _shellBorder = appBorder;
const _shellText = appText;
const _shellMuted = appSubtleText;

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
      backgroundColor: _shellBackground,
      appBar: PreferredSize(
        // Status-bar inset + content height (12 + 56 row + 12). Sizing to
        // content avoids the dead gap a fixed height used to leave below it.
        preferredSize: Size.fromHeight(MediaQuery.of(context).padding.top + 80),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _shellBackground,
              appPageBackgroundSoft,
              appPageBackgroundEnd,
            ],
          ),
        ),
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
    final accentColor = _accentForRole(roleLabel);
    final titleLine = displayName.isEmpty
        ? roleLabel
        : '$displayName • $roleLabel';

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: mobileContentMaxWidth),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: appSurface,
            border: Border(bottom: BorderSide(color: _shellBorder)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  _LogoBadge(accentColor: accentColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'BoxOS',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: _shellText,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          titleLine,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: _shellMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (availableRoles.length > 1) ...[
                    _HeaderIconButton(
                      icon: Icons.swap_horiz_rounded,
                      tooltip: 'Switch Role',
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
                    const SizedBox(width: 4),
                  ],
                  _HeaderIconButton(
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Notifications',
                    badge: unreadNotifications,
                    onTap: onNotificationsTap,
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onProfileTap,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: accentColor.withOpacity(0.14),
                      child: Text(
                        _initials(displayName),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: _shellText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

  static Color _accentForRole(String roleLabel) {
    switch (roleLabel.toLowerCase()) {
      case 'admin':
        return appPrimary;
      case 'trainer':
        return _shellBlue;
      default:
        return appPrimary;
    }
  }
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, accentColor.withOpacity(0.12)],
        ),
        border: Border.all(color: _shellBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(boxOsLogoAsset, fit: BoxFit.contain),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: outlined ? Colors.white : color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(outlined ? 0.32 : 0.20)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: outlined ? color : _shellText,
          fontWeight: FontWeight.w700,
        ),
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
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: appSurfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _shellBorder),
          ),
          child: Icon(icon, color: _shellText),
        ),
      ),
    );

    return Tooltip(
      message: tooltip,
      child: badge > 0
          ? Badge(
              isLabelVisible: true,
              label: Text(badge > 99 ? '99+' : '$badge'),
              child: button,
            )
          : button,
    );
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
    // Flat footer matching the header: white surface with a top border,
    // capped to the same width as the main content and centered. heightFactor
    // keeps the footer at its intrinsic height instead of filling the slot.
    // The NavigationBar is transparent so the surrounding white shows through
    // (incl. the bottom safe-area inset the bar manages itself).
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: mobileContentMaxWidth),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: appSurface,
            border: Border(top: BorderSide(color: _shellBorder)),
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              indicatorColor: const Color(0x1F2563EB),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  color: selected ? _shellBlue : _shellMuted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return IconThemeData(
                  color: selected ? _shellBlue : _shellMuted,
                );
              }),
            ),
            child: NavigationBar(
              selectedIndex: selectedIndex,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (index) {
                switch (index) {
                  case 0:
                    onHomeTap();
                    break;
                  case 1:
                    onMyBoxTap();
                    break;
                  case 2:
                    onLogbookTap();
                    break;
                  case 3:
                    onProfileTap();
                    break;
                }
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.fitness_center_outlined),
                  selectedIcon: Icon(Icons.fitness_center_rounded),
                  label: 'MyBox',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book_rounded),
                  label: 'Logbook',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
