import 'package:app/features/members/presentation/widgets/member_roster.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MemberRoster shows selected member in detail panel', (
    tester,
  ) async {
    final users = [
      RoleManagedUser(
        id: 1,
        membershipId: 10,
        email: 'owner@boxos.app',
        role: UserRole.admin,
        availableRoles: const [UserRole.admin],
        displayName: 'Demo Owner',
        nickname: 'owner',
        canEditRole: false,
        joinedAt: DateTime.utc(2026, 1, 1),
        totalBookings: 12,
        attendedBookings: 9,
        noShowBookings: 1,
        bookingRate: 75,
        newestPrTitle: 'Fran',
        newestPrScore: '3:42',
        newestPrAt: DateTime.utc(2026, 5, 1),
      ),
      RoleManagedUser(
        id: 2,
        membershipId: 11,
        email: 'trainer@boxos.app',
        role: UserRole.trainer,
        availableRoles: const [UserRole.athlete, UserRole.trainer],
        displayName: 'Demo Trainer',
        nickname: 'trainer',
        canEditRole: true,
        joinedAt: DateTime.utc(2026, 2, 1),
        totalBookings: 4,
        attendedBookings: 2,
        noShowBookings: 0,
        bookingRate: 50,
      ),
    ];

    // Desktop width: list and detail panel side by side. The roster fills
    // the height it is given, so it sits straight in the body.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MemberRoster(users: users, onSave: (_) async {}),
        ),
      ),
    );

    expect(find.text('Demo Owner'), findsOneWidget);
    expect(find.text('Booking rate'), findsOneWidget);
    expect(find.text('50.0%'), findsOneWidget);
    expect(find.text('No PR yet'), findsOneWidget);

    await tester.tap(find.text('Demo Owner'));
    await tester.pumpAndSettle();

    expect(find.text('Booking rate'), findsOneWidget);
    expect(find.text('75.0%'), findsOneWidget);
    expect(find.textContaining('3:42'), findsOneWidget);
  });
}
