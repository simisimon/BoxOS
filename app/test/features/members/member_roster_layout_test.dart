import 'package:app/app.dart';
import 'package:app/features/members/presentation/widgets/member_roster.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _users = [
  for (var i = 0; i < 60; i++)
    RoleManagedUser(
      id: i + 1,
      membershipId: i + 1,
      email: 'member$i@boxos.dev',
      role: UserRole.athlete,
      availableRoles: const [UserRole.athlete],
      displayName: 'Member $i',
      nickname: 'm$i',
      canEditRole: true,
      joinedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
    ),
];

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBoxOsTheme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: MemberRoster(users: _users, onSave: (_) async {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide: the detail stays put while the list scrolls', (
    tester,
  ) async {
    await _pump(tester, const Size(1280, 800));

    // A member far down the list (rows are sorted newest first).
    final row = find.text('Member 10');
    for (var i = 0; i < 30 && row.evaluate().isEmpty; i++) {
      await tester.dragFrom(const Offset(120, 500), const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    await tester.tap(row.first);
    await tester.pumpAndSettle();
    // Row and detail header both show the selected member.
    expect(find.text('Member 10'), findsNWidgets(2));

    final details = find.text('MEMBER DETAILS');
    final before = tester.getTopLeft(details);
    expect(before.dy, inInclusiveRange(0, 800));

    await tester.dragFrom(const Offset(120, 500), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(details), before);
    await tester.dragFrom(const Offset(120, 500), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(details), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow: tapping a member opens its detail page', (tester) async {
    await _pump(tester, const Size(390, 844));
    // No side panel on phones.
    expect(find.text('MEMBER DETAILS'), findsNothing);

    await tester.tap(find.text('Member 55'));
    await tester.pumpAndSettle();
    expect(find.text('MEMBER DETAILS'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('MEMBER DETAILS'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
