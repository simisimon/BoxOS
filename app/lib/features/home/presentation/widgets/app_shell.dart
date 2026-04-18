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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(76),
        child: _ShellHeader(
          displayName: displayName,
          roleLabel: roleLabel,
          availableRoles: availableRoles,
          onProfileTap: onHeaderProfileTap,
          onNotificationsTap: onNotificationsTap,
          onRoleSelected: onRoleSelected,
        ),
      ),
      body: LayoutBuilder(
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
    required this.onProfileTap,
    required this.onNotificationsTap,
    required this.onRoleSelected,
  });

  final String displayName;
  final String roleLabel;
  final List<UserRole> availableRoles;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationsTap;
  final ValueChanged<UserRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: MobileContent(
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Image.asset(boxOsLogoAsset, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'BoxOS',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      displayName.isEmpty
                          ? roleLabel
                          : '$displayName • $roleLabel',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (availableRoles.length > 1) ...[
                PopupMenuButton<UserRole>(
                  tooltip: 'Switch Role',
                  icon: const Icon(Icons.swap_horiz_rounded),
                  onSelected: onRoleSelected,
                  itemBuilder: (context) => availableRoles
                      .map(
                        (role) => PopupMenuItem<UserRole>(
                          value: role,
                          child: Text(role.label),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                onPressed: onNotificationsTap,
                icon: Badge(
                  isLabelVisible: true,
                  smallSize: 8,
                  label: const SizedBox.shrink(),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
                tooltip: 'Notifications',
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onProfileTap,
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    _initials(displayName),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
            ],
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: NavigationBar(
                selectedIndex: selectedIndex,
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
          );
        },
      ),
    );
  }
}
