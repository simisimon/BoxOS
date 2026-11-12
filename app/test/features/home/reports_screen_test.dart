import 'package:app/app.dart';
import 'package:app/features/admin_analytics/application/admin_analytics_controller.dart';
import 'package:app/features/admin_analytics/domain/models/admin_analytics_overview.dart';
import 'package:app/features/admin_analytics/presentation/screens/reports_screen.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_booking.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _overview = AdminAnalyticsOverview(
  windowDays: 14,
  activeMembers: 122,
  activeTrainers: 11,
  pendingJoinRequests: 0,
  newMembersInWindow: 6,
  roleMix: AdminAnalyticsRoleMix(
    athleteOnly: 105,
    trainerCapable: 11,
    adminCapable: 6,
  ),
  recentMembers: [],
  classesInWindow: 10,
  bookingsInWindow: 100,
  attendedInWindow: 81,
  noShowsInWindow: 9,
  attendanceRateInWindow: 81,
  utilizationRateInWindow: 75,
  noShowRateInWindow: 9,
  upcomingClassesNext7Days: 29,
  upcomingBookingsNext7Days: 0,
  upcomingCapacityNext7Days: 0,
  upcomingWaitlistSpotsNext7Days: 0,
  upcomingClassesWithWaitlistNext7Days: 0,
  upcomingFullClassesNext7Days: 0,
  dailyAttendance: [],
  pressureClasses: [],
  problemClasses: [],
);

ScheduleBooking _booking(int id, String status) => ScheduleBooking(
  userId: id,
  displayName: 'Member $id',
  nickname: 'm$id',
  attendanceStatus: status,
  isCurrentUser: false,
);

void main() {
  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    testWidgets('attendance report lists past classes at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminAnalyticsOverviewProvider.overrideWith(
              (ref) async => _overview,
            ),
            scheduleListProvider.overrideWith(
              (ref) async => [
                ScheduleClass(
                  id: 1,
                  gymId: 1,
                  title: 'Morning WOD',
                  classType: 'WOD',
                  startTime: yesterday,
                  durationMinutes: 60,
                  capacity: 4,
                  remainingSpots: 2,
                  bookedCount: 2,
                  bookings: [_booking(1, 'attended'), _booking(2, 'no_show')],
                ),
                // Future classes are not part of the report.
                ScheduleClass(
                  id: 2,
                  gymId: 1,
                  title: 'Tomorrow WOD',
                  classType: 'WOD',
                  startTime: DateTime.now().add(const Duration(days: 1)),
                  durationMinutes: 60,
                  capacity: 4,
                  remainingSpots: 4,
                ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: buildBoxOsTheme(),
            home: const Scaffold(body: ReportsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('81%'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Morning WOD'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Morning WOD'), findsOneWidget);
      if (size.width > 600) expect(find.text('50%'), findsOneWidget);
      expect(find.text('Tomorrow WOD'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
