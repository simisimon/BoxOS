import 'package:app/app.dart';
import 'package:app/features/admin_analytics/application/admin_analytics_controller.dart';
import 'package:app/features/admin_analytics/domain/models/owner_dashboard_data.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/home/presentation/widgets/owner_dashboard.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OwnerDashboardData _data() => OwnerDashboardData(
  membersAtRisk: 19,
  atRiskDays: 21,
  expiringMemberships: 11,
  expiringDays: 14,
  months: [
    for (var i = 0; i < 6; i++)
      DashboardMonth(
        month: DateTime(2026, 6 + i),
        newMembers: 2 + i,
        newMemberships: i,
        churnedMembers: i == 5 ? 2 : 1,
        registrations: 100 + 10 * i,
        attended: 80 + 5 * i,
        utilizationPercent: 50.0 + i,
      ),
  ],
);

void main() {
  for (final size in const [Size(1280, 900), Size(390, 844)]) {
    testWidgets('dashboard shows metrics, charts and activity at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ownerDashboardProvider.overrideWith((ref) async => _data()),
            pendingJoinRequestsProvider.overrideWith((ref) async => const []),
            pendingPlanRequestsProvider.overrideWith((ref) async => const []),
            programmingListProvider.overrideWith((ref) async => const []),
            scheduleListProvider.overrideWith(
              (ref) async => [
                ScheduleClass(
                  id: 1,
                  gymId: 1,
                  title: 'Evening WOD',
                  classType: 'WOD',
                  startTime: DateTime(now.year, now.month, now.day, 23),
                  durationMinutes: 45,
                  capacity: 12,
                  remainingSpots: 12,
                ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: buildBoxOsTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(child: OwnerDashboard()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Members at risk'), findsOneWidget);
      expect(find.text('19'), findsOneWidget);
      // Churn rose from 1 to 2: shown as a bad (↑) trend.
      expect(find.text('↑ 100%'), findsOneWidget);
      expect(find.text('Class utilisation'), findsOneWidget);
      expect(find.text('55%'), findsOneWidget);
      expect(find.text('Evening WOD'), findsOneWidget);
      expect(find.text('Manage programs'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
