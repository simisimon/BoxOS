import 'package:app/app.dart';
import 'package:app/features/announcements/data/repositories/api_announcement_repository.dart';
import 'package:app/features/announcements/domain/models/announcement.dart';
import 'package:app/features/announcements/domain/repositories/announcement_repository.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';
import 'package:app/features/calendar/domain/repositories/schedule_repository.dart';
import 'package:app/features/home/presentation/widgets/owner_dashboard.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:app/features/profile/domain/models/user_profile.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeScheduleRepository implements ScheduleRepository {
  int? booked;

  @override
  Future<void> bookClass({required int classId}) async => booked = classId;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeAnnouncementRepository implements AnnouncementRepository {
  @override
  Future<List<Announcement>> fetchAnnouncements() async => [
    Announcement(
      id: 1,
      gymId: 1,
      title: 'Open Gym on Sunday',
      description: 'Doors open at 10.',
      imageUrl: '',
      authorName: 'Box Owner',
      createdAt: DateTime(2026, 11, 12),
      updatedAt: DateTime(2026, 11, 12),
      likeCount: 2,
      likedByMe: false,
      commentCount: 0,
      comments: const [],
      canManage: false,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

const _athlete = UserProfile(
  email: 'athlete@boxos.app',
  accountType: AccountType.athlete,
  role: UserRole.athlete,
  availableRoles: [UserRole.athlete],
  displayName: 'Clara Haas',
  nickname: 'clara',
  notificationPreferences: NotificationPreferences(
    bookingConfirmations: true,
    waitlistPromotions: true,
    paymentIssues: true,
    wodPosted: true,
    prAchievements: true,
    announcementActivity: true,
  ),
  activeGym: GymSummary(
    id: 1,
    name: 'Test Box',
    slug: 'test-box',
    logoUrl: '',
    timezone: 'Europe/Berlin',
  ),
  memberships: [],
);

DateTime _tomorrowAt(int hour) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1, hour);
}

ScheduleClass _class(int id, String title, {ScheduleTrainer? trainer}) =>
    ScheduleClass(
      id: id,
      gymId: 1,
      title: title,
      classType: 'WOD',
      startTime: _tomorrowAt(18),
      durationMinutes: 60,
      capacity: 12,
      remainingSpots: 12,
      assignedTrainer: trainer,
    );

Future<_FakeScheduleRepository> _pump(
  WidgetTester tester,
  Size size,
  Widget child,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final schedule = _FakeScheduleRepository();
  final tomorrow = _tomorrowAt(0);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentProfileProvider.overrideWith((ref) async => _athlete),
        scheduleRepositoryProvider.overrideWithValue(schedule),
        announcementRepositoryProvider.overrideWithValue(
          _FakeAnnouncementRepository(),
        ),
        programmingListProvider.overrideWith(
          (ref) async => [
            DailyWorkout(
              id: 1,
              gymId: 1,
              scheduledDate: tomorrow,
              title: 'Fran',
              sections: const [
                DailyWorkoutSection(
                  title: 'Metcon',
                  description: '21-15-9 Thrusters + Pull-ups',
                  scoreType: WorkoutSectionScore.time,
                ),
              ],
              status: DailyWorkoutStatus.published,
              publishedAt: tomorrow,
              canEdit: false,
            ),
          ],
        ),
        scheduleListProvider.overrideWith(
          (ref) async => [
            _class(1, 'Evening WOD'),
            _class(
              2,
              'Coach Alex WOD',
              trainer: const ScheduleTrainer(
                id: 7,
                displayName: 'Coach Alex',
                nickname: 'alex',
              ),
            ),
          ],
        ),
      ],
      child: MaterialApp(
        theme: buildBoxOsTheme(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The classes are tomorrow, so the test never depends on the clock.
  await tester.tap(find.byTooltip('Next day'));
  await tester.pumpAndSettle();
  return schedule;
}

void main() {
  for (final size in const [Size(1280, 900), Size(390, 844)]) {
    testWidgets('athlete Home books a class next to the WOD at $size', (
      tester,
    ) async {
      final schedule = await _pump(tester, size, const AthleteHome());

      expect(find.text('WOD of the day'), findsOneWidget);
      expect(find.text('Fran'), findsOneWidget);
      expect(find.text('21-15-9 Thrusters + Pull-ups'), findsOneWidget);
      expect(find.text('Manage programs'), findsNothing);
      expect(find.text('Open Gym on Sunday'), findsOneWidget);

      // Phones stack the row: the class name sits above its Book button.
      final title = tester.getRect(find.text('Evening WOD'));
      final book = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Book').first,
      );
      expect(title.bottom <= book.top, size.width < 600);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Book').first);
      await tester.pumpAndSettle();
      expect(schedule.booked, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('trainer Dashboard starts on the classes they coach at $size', (
      tester,
    ) async {
      await _pump(tester, size, const TrainerDashboard(userId: 7));

      expect(find.text('Classes this week'), findsOneWidget);
      expect(find.text('Coach Alex WOD'), findsOneWidget);
      expect(find.text('Evening WOD'), findsNothing);
      // Trainers don't book from here.
      expect(find.widgetWithText(OutlinedButton, 'Book'), findsNothing);

      await tester.tap(find.text('Coached by me'));
      await tester.pumpAndSettle();
      expect(find.text('Evening WOD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
