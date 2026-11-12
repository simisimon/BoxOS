import 'package:app/app.dart';
import 'package:app/features/home/presentation/widgets/app_shell.dart';
import 'package:app/features/home/presentation/widgets/shell_destinations.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _shell({void Function(UserRole)? onRole}) => MaterialApp(
  theme: buildBoxOsTheme(),
  home: AuthenticatedScaffold(
    selectedBranchIndex: kHomeBranch,
    destinations: destinationsForView(
      accountType: AccountType.admin,
      role: UserRole.admin,
    ),
    displayName: 'Jordan Cole',
    email: 'owner@boxos.dev',
    gymName: 'Iron Forge CrossFit',
    roleLabel: UserRole.admin.label,
    availableRoles: const [UserRole.admin, UserRole.athlete],
    unreadNotifications: 3,
    branchBadges: const {kMembersBranch: 8},
    body: const SizedBox.expand(),
    onSelectBranch: (_) {},
    onHeaderProfileTap: () {},
    onNotificationsTap: () {},
    onRoleSelected: onRole ?? (_) {},
  ),
);

void main() {
  for (final width in [1280.0, 900.0]) {
    testWidgets('sidebar lays out and toggles at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_shell());
      // Wide windows start expanded, 840–1199 px collapsed.
      expect(
        find.text('Members').hitTestable(),
        width >= 1200 ? findsOneWidget : findsNothing,
      );

      await tester.tap(find.byIcon(Icons.view_sidebar_outlined));
      await tester.pumpAndSettle();
      expect(
        find.text('Members').hitTestable(),
        width >= 1200 ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('account menu offers the other role only', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    UserRole? picked;

    await tester.pumpWidget(_shell(onRole: (r) => picked = r));
    await tester.tap(find.text('Jordan Cole'));
    await tester.pumpAndSettle();

    expect(find.text('Switch to ${UserRole.admin.label}'), findsNothing);
    await tester.tap(find.text('Switch to ${UserRole.athlete.label}'));
    await tester.pumpAndSettle();
    expect(picked, UserRole.athlete);
    expect(tester.takeException(), isNull);
  });
}
