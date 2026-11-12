import 'package:app/app.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/members/domain/member_booking.dart';
import 'package:app/features/members/presentation/widgets/member_roster.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _users = [
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
    displayName: 'Anna Trainer',
    nickname: 'trainer',
    canEditRole: true,
    joinedAt: DateTime.utc(2026, 2, 1),
  ),
];

Future<void> _pump(WidgetTester tester, Widget child, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBoxOsTheme(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('roster table sorts, filters and opens a row', (tester) async {
    RoleManagedUser? opened;
    await _pump(
      tester,
      MemberRoster(users: _users, onOpen: (u) => opened = u),
      const Size(1280, 800),
    );

    expect(find.text('owner@boxos.app'), findsOneWidget);
    expect(find.text('Showing 2 of 2'), findsOneWidget);
    // Sorted by name, A to Z.
    expect(
      tester.getTopLeft(find.text('Anna Trainer')).dy,
      lessThan(tester.getTopLeft(find.text('Demo Owner')).dy),
    );

    await tester.tap(find.text('Trainer 1'));
    await tester.pumpAndSettle();
    expect(find.text('Demo Owner'), findsNothing);
    expect(find.text('Showing 1 of 2'), findsOneWidget);

    await tester.tap(find.text('Anna Trainer'));
    expect(opened?.id, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow roster drops the email column', (tester) async {
    await _pump(
      tester,
      MemberRoster(users: _users, onOpen: (_) {}),
      const Size(390, 844),
    );
    expect(find.text('owner@boxos.app'), findsNothing);
    expect(find.text('Demo Owner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    testWidgets('detail shows overview and classes at ${size.width}', (
      tester,
    ) async {
      final now = DateTime.now();
      await _pump(
        tester,
        MemberDetailView(
          user: _users.first,
          saving: false,
          onSave: (_) async {},
          planSection: const SizedBox(height: 80),
          membershipsTab: const Text('plans table'),
          bookings: Future.value([
            MemberBooking(
              classId: 1,
              title: 'Evening WOD',
              type: ClassType.wod,
              start: now.add(const Duration(days: 1)),
              end: now.add(const Duration(days: 1, hours: 1)),
              trainerName: 'Anna Trainer',
              status: 'booked',
            ),
            MemberBooking(
              classId: 2,
              title: 'Morning WOD',
              type: ClassType.wod,
              start: now.subtract(const Duration(days: 2)),
              end: now.subtract(const Duration(days: 2, hours: -1)),
              trainerName: '',
              status: 'attended',
            ),
          ]),
        ),
        size,
      );

      expect(find.text('75.0%'), findsOneWidget);
      expect(find.textContaining('3:42'), findsOneWidget);

      // The tab bar scrolls on phones.
      await tester.ensureVisible(find.text('Classes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Classes'));
      await tester.pumpAndSettle();
      expect(find.text('Evening WOD'), findsOneWidget);
      expect(find.text('REGISTERED'), findsOneWidget);

      await tester.tap(find.text('History 1'));
      await tester.pumpAndSettle();
      expect(find.text('ATTENDED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
