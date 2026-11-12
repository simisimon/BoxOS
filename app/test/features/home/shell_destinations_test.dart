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

    test('the athlete tab set fits the bottom-nav budget', () {
      expect(athlete().map((d) => d.label), [
        'Home',
        'My Box',
        'Community',
        'Profile',
      ]);
    });

    test('the owner tab set follows the admin reference', () {
      // The box chat is a tab of Messages; there is no logbook.
      expect(owner().map((d) => d.label), [
        'Dashboard',
        'Classes',
        'Programs',
        'Members',
        'Reports',
        'Messages',
        'Memberships',
        'Settings',
        'Profile',
      ]);
    });

    test('only owners get the Settings tab', () {
      expect(owner().map((d) => d.branchIndex), contains(kBoxSettingsBranch));
      expect(
        athlete().map((d) => d.branchIndex),
        isNot(contains(kBoxSettingsBranch)),
      );
      final trainer = destinationsForView(
        accountType: AccountType.athlete,
        role: UserRole.trainer,
      );
      expect(
        trainer.map((d) => d.branchIndex),
        isNot(contains(kBoxSettingsBranch)),
      );
    });

    test('a trainer sees the athlete tab set plus Programs', () {
      final trainer = destinationsForView(
        accountType: AccountType.athlete,
        role: UserRole.trainer,
      );
      expect(trainer.map((d) => d.label), [
        'Home',
        'My Box',
        'Programs',
        'Community',
        'Profile',
      ]);
    });

    test('every destination points at a distinct branch', () {
      for (final set in [athlete(), owner()]) {
        final branches = set.map((d) => d.branchIndex).toList();
        expect(branches.toSet(), hasLength(branches.length));
      }
    });
  });
}
