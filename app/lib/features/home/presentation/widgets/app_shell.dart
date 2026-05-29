import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';

const boxOsLogoAsset = 'assets/images/boxOS_logo.png';
const _shellBlue = Color(0xFF2563EB);
const _shellBackground = Color(0xFFF5F9FF);
const _shellSurface = Colors.white;
const _shellBorder = Color(0xFFD8E4F2);
const _shellText = Color(0xFF0F172A);
const _shellMuted = Color(0xFF64748B);

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
      extendBody: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(132),
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
              Color(0xFFEAF2FF),
              Color(0xFFF9FBFF),
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
    final titleLine = displayName.isEmpty ? roleLabel : '$displayName • $roleLabel';

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: MobileContent(
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: _shellSurface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _shellBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x120F172A),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Row(
              children: [
                _LogoBadge(accentColor: accentColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BoxOS',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _shellText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        titleLine,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _shellMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _HeaderChip(label: roleLabel, color: accentColor),
                          _HeaderChip(
                            label: unreadNotifications > 0
                                ? '$unreadNotifications unread'
                                : 'Inbox clear',
                            color: const Color(0xFF0EA5A4),
                            outlined: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    if (availableRoles.length > 1)
                      _HeaderIconButton(
                        icon: Icons.swap_horiz_rounded,
                        tooltip: 'Switch Role',
                        onTap: () async {
                          final renderBox = context.findRenderObject() as RenderBox?;
                          final position = renderBox == null
                              ? const RelativeRect.fromLTRB(0, 0, 0, 0)
                              : RelativeRect.fromRect(
                                  Rect.fromPoints(
                                    renderBox.localToGlobal(Offset.zero),
                                    renderBox.localToGlobal(renderBox.size.bottomRight(Offset.zero)),
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
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _HeaderIconButton(
                          icon: Icons.notifications_none_rounded,
                          tooltip: 'Notifications',
                          badge: unreadNotifications,
                          onTap: onNotificationsTap,
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onProfileTap,
                          child: CircleAvatar(
                            radius: 22,
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
                  ],
                ),
              ],
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
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  static Color _accentForRole(String roleLabel) {
    switch (roleLabel.toLowerCase()) {
      case 'admin':
        return const Color(0xFFEA580C);
      case 'trainer':
        return _shellBlue;
      default:
        return const Color(0xFF0EA5A4);
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
          colors: [
            Colors.white,
            accentColor.withOpacity(0.12),
          ],
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
            color: const Color(0xFFF8FBFF),
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
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding =
              constraints.maxWidth > mobileContentMaxWidth
              ? (constraints.maxWidth - mobileContentMaxWidth) / 2
              : 0.0;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16 + horizontalPadding,
              8,
              16 + horizontalPadding,
              12,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: _shellSurface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _shellBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  backgroundColor: Colors.transparent,
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
                  height: 74,
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
          );
        },
      ),
    );
  }
}
