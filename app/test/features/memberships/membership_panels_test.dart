import 'package:app/app.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:app/features/memberships/presentation/member_plan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _plan = MembershipPlan(
  id: 7,
  name: 'Unlimited',
  description: '',
  type: PlanType.unlimited,
  priceCents: 12000,
  currency: 'EUR',
  billingPeriod: BillingPeriod.monthly,
);

Future<void> _open(
  WidgetTester tester,
  Size size,
  Future<void> Function(BuildContext) open,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBoxOsTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    testWidgets('create membership panel previews payments at ${size.width}', (
      tester,
    ) async {
      PlanAssignment? result;
      await _open(tester, size, (context) async {
        result = await showPlanAssignmentPanel(
          context,
          title: 'Create membership',
          confirmLabel: 'Create membership',
          plans: const [_plan],
          memberName: 'Clara Haas',
        );
      });

      expect(find.text('Clara Haas'), findsOneWidget);
      expect(find.text('First payment'), findsOneWidget);
      expect(find.textContaining('New cycle'), findsOneWidget);
      expect(find.text('N/A'), findsOneWidget);

      // A member price below the plan price shows as a discount.
      await tester.enterText(find.byType(TextFormField), '100');
      await tester.pumpAndSettle();
      expect(find.textContaining('20'), findsWidgets);
      expect(find.text('N/A'), findsNothing);

      await tester.tap(find.text('Create membership').last);
      await tester.pumpAndSettle();
      expect(result?.planId, 7);
      expect(result?.priceCents, 10000);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('membership detail panel ends from the menu', (tester) async {
    var ended = false;
    await _open(tester, const Size(1280, 800), (context) {
      return showMembershipDetailPanel(
        context,
        plan: const MemberPlan(
          id: 1,
          userId: 2,
          planId: 7,
          state: MemberPlanState.current,
          planName: 'Unlimited',
          type: PlanType.unlimited,
          priceCents: 12000,
          currency: 'EUR',
          billingPeriod: BillingPeriod.monthly,
          paymentStatus: PaymentStatus.paid,
          startsOn: '2026-11-01',
        ),
        memberName: 'Clara Haas',
        onPaymentChanged: (_) {},
        onEnd: () => ended = true,
      );
    });

    expect(find.text('Unlimited'), findsOneWidget);
    expect(find.text('2026-11-01'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End membership'));
    await tester.pumpAndSettle();
    expect(ended, isTrue);
    expect(find.text('2026-11-01'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
