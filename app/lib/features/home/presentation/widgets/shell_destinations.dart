import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';

/// Branch indices in the router's [StatefulShellRoute]. The visible tab order
/// varies by role (see [destinationsForView]), so destinations point at a
/// branch index instead of assuming the nav position equals the branch.
const int kHomeBranch = 0;
const int kMyBoxBranch = 1;
const int kLogbookBranch = 2;
const int kMembersBranch = 3;
const int kCommunityBranch = 4;
const int kProfileBranch = 5;

/// Tracking has no tab of its own: it answers the same question as the logbook
/// ("how am I doing"), so it is reached from there. The router still keeps the
/// branch, which is why the index stays.
const int kTrackingBranch = 6;

/// A single bottom-nav / rail destination. [branchIndex] is the shell branch it
/// activates, decoupling the role-specific tab order from the fixed branch
/// order in the router.
class ShellDestination {
  const ShellDestination({
    required this.branchIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final int branchIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
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
    branchIndex: kLogbookBranch,
    icon: Icons.menu_book_outlined,
    activeIcon: Icons.menu_book_rounded,
    label: 'Logbook',
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
    label: 'Schedule',
  ),
  ShellDestination(
    branchIndex: kMembersBranch,
    icon: Icons.groups_outlined,
    activeIcon: Icons.groups_rounded,
    label: 'Members',
  ),
  ShellDestination(
    branchIndex: kCommunityBranch,
    icon: Icons.chat_bubble_outline_rounded,
    activeIcon: Icons.chat_bubble_rounded,
    label: 'Community',
  ),
  ShellDestination(
    branchIndex: kLogbookBranch,
    icon: Icons.menu_book_outlined,
    activeIcon: Icons.menu_book_rounded,
    label: 'Logbook',
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

/// The tab that should read as active for [branchIndex].
///
/// Tracking has no tab of its own and is entered from the logbook, so it keeps
/// the Logbook tab lit instead of falling back to the first one.
int navBranchFor(int branchIndex) =>
    branchIndex == kTrackingBranch ? kLogbookBranch : branchIndex;

/// The nav destinations for the current account/role pair.
List<ShellDestination> destinationsForView({
  required AccountType? accountType,
  required UserRole? role,
}) => isOwnerView(accountType: accountType, role: role)
    ? _ownerDestinations
    : _athleteDestinations;
