import 'package:app/app.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:app/features/memberships/presentation/screens/memberships_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository implements MembershipRepository {
  @override
  Future<MembershipSettings> fetchSettings() async =>
      const MembershipSettings(currency: 'EUR', requirePlanForBooking: false);

  @override
  Future<List<MembershipPlan>> fetchPlans({
    bool includeArchived = false,
  }) async => const [
    MembershipPlan(
      id: 1,
      name: 'Unlimited',
      description: '',
      type: PlanType.unlimited,
      priceCents: 12900,
      currency: 'EUR',
      billingPeriod: BillingPeriod.monthly,
      allowedClassTypes: ['WOD', 'Open Gym'],
      activeMemberCount: 42,
    ),
    MembershipPlan(
      id: 2,
      name: 'Old Drop-in',
      description: '',
      type: PlanType.tokenPack,
      priceCents: 2000,
      currency: 'EUR',
      billingPeriod: BillingPeriod.oneTime,
      tokenCount: 1,
      isArchived: true,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    testWidgets('plans table and plan panel at ${size.width}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            membershipRepositoryProvider.overrideWithValue(_FakeRepository()),
          ],
          child: MaterialApp(
            theme: buildBoxOsTheme(),
            home: const Scaffold(body: MembershipsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unlimited'), findsWidgets);
      expect(find.text('Old Drop-in'), findsNothing);
      expect(find.text('Showing 1 of 1'), findsOneWidget);

      await tester.tap(find.text('Archived 1'));
      await tester.pumpAndSettle();
      expect(find.text('Old Drop-in'), findsOneWidget);

      // Row click opens the plan panel with the plan's name as title.
      await tester.tap(find.text('Old Drop-in'));
      await tester.pumpAndSettle();
      expect(find.byType(AppSidePanel), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
