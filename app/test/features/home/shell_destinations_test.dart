import 'package:app/features/home/presentation/widgets/shell_destinations.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('destinationsForView', () {
    List<ShellDestination> athlete() => destinationsForView(
      accountType: AccountType.athlete,
      role: UserRole.athlete,
    );
    List<ShellDestination> owner() => destinationsForView(
      accountType: AccountType.admin,
      role: UserRole.admin,
    );

    test('the athlete tab set fits the five-tab bottom-nav budget', () {
      expect(athlete().length, 5);
      expect(athlete().map((d) => d.label), [
        'Home',
        'My Box',
        'Community',
        'Logbook',
        'Profile',
      ]);
    });

    test('the owner tab set is still one over budget', () {
      // Dropping Tracking took the owner from seven tabs to six. The last one
      // goes when the logbook rebuild moves athlete history into the member
      // detail, where a coach actually needs it. Tighten this to 5 then.
      expect(owner().length, 6);
      expect(owner().map((d) => d.label), [
        'Dashboard',
        'Schedule',
        'Members',
        'Community',
        'Logbook',
        'Profile',
      ]);
    });

    test('Tracking has no tab of its own', () {
      expect(
        athlete().map((d) => d.branchIndex),
        isNot(contains(kTrackingBranch)),
      );
      expect(
        owner().map((d) => d.branchIndex),
        isNot(contains(kTrackingBranch)),
      );
      expect(athlete().map((d) => d.label), isNot(contains('Tracking')));
      expect(owner().map((d) => d.label), isNot(contains('Tracking')));
    });

    test('both roles keep the logbook, which is where tracking is entered', () {
      expect(athlete().map((d) => d.branchIndex), contains(kLogbookBranch));
      expect(owner().map((d) => d.branchIndex), contains(kLogbookBranch));
    });

    test('a trainer sees the athlete tab set', () {
      final trainer = destinationsForView(
        accountType: AccountType.athlete,
        role: UserRole.trainer,
      );
      expect(trainer.map((d) => d.label), athlete().map((d) => d.label));
    });

    test('every destination points at a distinct branch', () {
      for (final set in [athlete(), owner()]) {
        final branches = set.map((d) => d.branchIndex).toList();
        expect(branches.toSet(), hasLength(branches.length));
      }
    });
  });

  group('navBranchFor', () {
    test('tracking lights the Logbook tab instead of falling back to Home', () {
      expect(navBranchFor(kTrackingBranch), kLogbookBranch);
    });

    test('every other branch maps to itself', () {
      for (final branch in [
        kHomeBranch,
        kMyBoxBranch,
        kLogbookBranch,
        kMembersBranch,
        kCommunityBranch,
        kProfileBranch,
      ]) {
        expect(navBranchFor(branch), branch);
      }
    });

    test('the mapped branch is always a visible tab for some role', () {
      final visible = {
        ...destinationsForView(
          accountType: AccountType.athlete,
          role: UserRole.athlete,
        ).map((d) => d.branchIndex),
        ...destinationsForView(
          accountType: AccountType.admin,
          role: UserRole.admin,
        ).map((d) => d.branchIndex),
      };
      expect(visible, contains(navBranchFor(kTrackingBranch)));
    });
  });
}
