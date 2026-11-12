import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';

/// Branch indices in the router's [StatefulShellRoute]. The visible tab order
/// varies by role (see [destinationsForView]), so destinations point at a
/// branch index instead of assuming the nav position equals the branch.
const int kHomeBranch = 0;
const int kMyBoxBranch = 1;
const int kMembersBranch = 2;
const int kCommunityBranch = 3;
const int kProfileBranch = 4;

/// Owner-only box configuration.
const int kBoxSettingsBranch = 5;

/// Owner-only plan catalogue (docs/admin-ui-reference.md §9).
const int kMembershipsBranch = 6;

/// WOD programming board (docs/admin-ui-reference.md §3); owners and
/// trainers.
const int kProgramsBranch = 7;

/// Owner reports (docs/admin-ui-reference.md §8); Attendance for now.
const int kReportsBranch = 8;

/// Owner messages: announcements and box chat (docs/admin-ui-reference.md §5).
const int kMessagesBranch = 9;

const _programsDestination = ShellDestination(
  branchIndex: kProgramsBranch,
  icon: Icons.view_week_outlined,
  activeIcon: Icons.view_week_rounded,
  label: 'Programs',
);

/// A single bottom-nav / rail destination. [branchIndex] is the shell branch it
/// activates, decoupling the role-specific tab order from the fixed branch
/// order in the router.
class ShellDestination {
  const ShellDestination({
    required this.branchIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.children = const [],
  });

  final int branchIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Submenu entries (label, location) shown under this item in the sidebar
  /// (the reference's `Settings ▸`). Phones ignore them.
  final List<(String, String)> children;
}

/// Athlete & trainer keep the original athlete-centric tab set.
const List<ShellDestination> _athleteDestinations = [
  ShellDestination(
    branchIndex: kHomeBranch,
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
    label: 'Home',
  ),
  ShellDestination(
    branchIndex: kMyBoxBranch,
    icon: Icons.fitness_center_outlined,
    activeIcon: Icons.fitness_center_rounded,
    label: 'My Box',
  ),
  ShellDestination(
    branchIndex: kCommunityBranch,
    icon: Icons.chat_bubble_outline_rounded,
    activeIcon: Icons.chat_bubble_rounded,
    label: 'Community',
  ),
  ShellDestination(
    branchIndex: kProfileBranch,
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
    label: 'Profile',
  ),
];

/// Owner (admin account + admin role) gets an operations-centric tab set.
const List<ShellDestination> _ownerDestinations = [
  ShellDestination(
    branchIndex: kHomeBranch,
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard_rounded,
    label: 'Dashboard',
  ),
  ShellDestination(
    branchIndex: kMyBoxBranch,
    icon: Icons.event_outlined,
    activeIcon: Icons.event_rounded,
    label: 'Classes',
  ),
  _programsDestination,
  ShellDestination(
    branchIndex: kMembersBranch,
    icon: Icons.groups_outlined,
    activeIcon: Icons.groups_rounded,
    label: 'Members',
  ),
  ShellDestination(
    branchIndex: kReportsBranch,
    icon: Icons.insert_chart_outlined_rounded,
    activeIcon: Icons.insert_chart_rounded,
    label: 'Reports',
  ),
  ShellDestination(
    branchIndex: kMessagesBranch,
    icon: Icons.mail_outline_rounded,
    activeIcon: Icons.mail_rounded,
    label: 'Messages',
  ),
  ShellDestination(
    branchIndex: kMembershipsBranch,
    icon: Icons.card_membership_outlined,
    activeIcon: Icons.card_membership_rounded,
    label: 'Memberships',
  ),
  // The box chat is a tab of Messages for owners, not a nav item.
  ShellDestination(
    branchIndex: kBoxSettingsBranch,
    icon: Icons.tune_outlined,
    activeIcon: Icons.tune_rounded,
    label: 'Settings',
    // Mirrors SettingsSection in box_settings_screen.dart.
    children: [
      ('Gym profile', '/box-settings?section=profile'),
      ('Booking rules', '/box-settings?section=booking-rules'),
      ('Class types', '/box-settings?section=class-types'),
      ('Payments', '/box-settings?section=payments'),
      ('Notifications', '/box-settings?section=notifications'),
    ],
  ),
  ShellDestination(
    branchIndex: kProfileBranch,
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
    label: 'Profile',
  ),
];

/// Whether the given account/role pair should see the owner (box-operator)
/// experience. Mirrors the check used across the home/dashboard surfaces.
bool isOwnerView({
  required AccountType? accountType,
  required UserRole? role,
}) => accountType == AccountType.admin && role == UserRole.admin;

/// The nav destinations for the current account/role pair.
List<ShellDestination> destinationsForView({
  required AccountType? accountType,
  required UserRole? role,
}) => isOwnerView(accountType: accountType, role: role)
    ? _ownerDestinations
    : role == UserRole.trainer
    // Trainers program WODs too; Programs sits after My Box.
    ? [
        ..._athleteDestinations.take(2),
        _programsDestination,
        ..._athleteDestinations.skip(2),
      ]
    : _athleteDestinations;
