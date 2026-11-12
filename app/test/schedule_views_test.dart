import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/class_template.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';
import 'package:app/features/calendar/domain/repositories/schedule_repository.dart';
import 'package:app/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/programming/domain/repositories/programming_repository.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/gym_membership.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:app/features/profile/domain/models/user_profile.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:app/app.dart';
import 'package:app/features/calendar/domain/models/schedule_booking.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _gym = GymSummary(
  id: 1,
  name: 'Test Box',
  slug: 'test-box',
  logoUrl: '',
  timezone: 'Europe/Berlin',
);

const _owner = UserProfile(
  email: 'owner@boxos.app',
  accountType: AccountType.admin,
  role: UserRole.admin,
  availableRoles: [UserRole.admin, UserRole.trainer, UserRole.athlete],
  displayName: 'Box Owner',
  nickname: 'owner',
  notificationPreferences: NotificationPreferences(
    bookingConfirmations: true,
    waitlistPromotions: true,
    paymentIssues: true,
    wodPosted: true,
    prAchievements: true,
    announcementActivity: true,
  ),
  activeGym: _gym,
  memberships: [
    GymMembership(
      gym: _gym,
      role: UserRole.admin,
      availableRoles: [UserRole.admin, UserRole.trainer, UserRole.athlete],
      status: 'active',
    ),
  ],
);

const _athlete = UserProfile(
  email: 'owner@boxos.app',
  accountType: AccountType.admin,
  role: UserRole.athlete,
  availableRoles: [UserRole.admin, UserRole.trainer, UserRole.athlete],
  displayName: 'Box Owner',
  nickname: 'owner',
  notificationPreferences: NotificationPreferences(
    bookingConfirmations: true,
    waitlistPromotions: true,
    paymentIssues: true,
    wodPosted: true,
    prAchievements: true,
    announcementActivity: true,
  ),
  activeGym: _gym,
  memberships: [
    GymMembership(
      gym: _gym,
      role: UserRole.admin,
      availableRoles: [UserRole.admin, UserRole.trainer, UserRole.athlete],
      status: 'active',
    ),
  ],
);

DateTime _tomorrowAt(int hour) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1, hour);
}

/// Tomorrow's 17:30 CrossFit, generated from the weekly class with id 1.
final _seriesSession = ScheduleClass(
  id: 10,
  gymId: 1,
  title: 'CrossFit',
  classType: 'WOD',
  startTime: _tomorrowAt(17).add(const Duration(minutes: 30)),
  durationMinutes: 60,
  capacity: 20,
  classTemplateId: 1,
  remainingSpots: 20,
);

class _FakeScheduleRepository implements ScheduleRepository {
  ClassTemplateDraft? lastCreatedTemplate;
  int? lastBookedClassId;
  int? lastRemovedUserId;

  @override
  Future<void> cancelBooking({required int classId, int? userId}) async {
    lastRemovedUserId = userId;
  }

  @override
  Future<void> bookClass({required int classId}) async {
    lastBookedClassId = classId;
  }

  @override
  Future<List<ClassTemplate>> fetchTemplates() async => const [
    ClassTemplate(
      id: 1,
      title: 'CrossFit',
      classType: ClassType.wod,
      weekdays: [1, 2, 3, 4, 5],
      hour: 17,
      minute: 30,
      durationMinutes: 60,
      capacity: 20,
    ),
  ];

  @override
  Future<ClassTemplate> createTemplate(ClassTemplateDraft draft) async {
    lastCreatedTemplate = draft;
    return ClassTemplate(
      id: 2,
      title: draft.title,
      classType: ClassType.fromWire(draft.classType),
      weekdays: draft.weekdays,
      hour: draft.hour,
      minute: draft.minute,
      durationMinutes: draft.durationMinutes,
      capacity: draft.capacity,
    );
  }

  @override
  Future<List<ScheduleTrainer>> fetchTrainers() async => const [
    ScheduleTrainer(id: 7, displayName: 'Coach Alex', nickname: 'alex'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeProgrammingRepository implements ProgrammingRepository {
  // Today's WOD, so the week view renders a full workout card (log) and
  // not only empty days.
  @override
  Future<List<DailyWorkout>> fetchWorkouts() async {
    final now = DateTime.now();
    return [
      DailyWorkout(
        id: 1,
        gymId: 1,
        scheduledDate: DateTime(now.year, now.month, now.day),
        title: 'Fran',
        sections: const [
          DailyWorkoutSection(
            title: 'Metcon',
            description: '21-15-9 Thrusters + Pull-ups',
            scoreType: WorkoutSectionScore.time,
          ),
        ],
        status: DailyWorkoutStatus.published,
        publishedAt: now,
        canEdit: true,
        myWorkoutLog: null,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Pumps the schedule with the real app theme: it makes FilledButtons
/// full-width, which breaks any button placed in a Row — a failure the
/// default test theme would hide.
Future<_FakeScheduleRepository> _pumpSchedule(
  WidgetTester tester,
  Size size, {
  UserProfile profile = _owner,
  ScheduleClass? session,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = _FakeScheduleRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentProfileProvider.overrideWith((ref) async => profile),
        scheduleRepositoryProvider.overrideWithValue(repository),
        scheduleListProvider.overrideWith(
          (ref) async => [session ?? _seriesSession],
        ),
        programmingRepositoryProvider.overrideWithValue(
          _FakeProgrammingRepository(),
        ),
      ],
      child: MaterialApp(
        theme: buildBoxOsTheme(),
        home: const Scaffold(body: SafeArea(child: MyBoxScreen())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

/// Fails with the full Flutter diagnostics (including the widget that caused
/// a layout or paint error), not just its one-line summary.
void _expectNoException(WidgetTester tester) {
  final error = tester.takeException();
  expect(
    error,
    isNull,
    reason: error is FlutterError ? error.toStringDeep() : '$error',
  );
}

/// Opens tomorrow's CrossFit from the week; next week when today is Sunday.
Future<void> _openTomorrowClass(WidgetTester tester) async {
  if (_tomorrowAt(0).weekday == DateTime.monday) {
    await tester.tap(find.byTooltip('Next week'));
    await tester.pumpAndSettle();
  }
  // The managers' hour grid scrolls sideways on phones.
  await tester.ensureVisible(find.text('CrossFit'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('CrossFit'));
  await tester.pumpAndSettle();
  _expectNoException(tester);
}

void main() {
  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    testWidgets('Week view shows WODs per day and switches weeks at $size', (
      tester,
    ) async {
      // The day columns with WODs are the athletes' view.
      await _pumpSchedule(tester, size, profile: _athlete);
      _expectNoException(tester);
      // Today's WOD shows on its day slip; tapping it opens the full card.
      expect(find.text('Fran'), findsOneWidget);
      await tester.tap(find.text('Fran'));
      await tester.pumpAndSettle();
      _expectNoException(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Log Results'), findsOneWidget);
      expect(find.text('Whiteboard'), findsNothing);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Today'), findsNothing);

      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();
      _expectNoException(tester);
      expect(find.text('Today'), findsOneWidget);

      // Programming moved to the Programs page: the week shows WODs only.
      expect(find.text('Add WOD'), findsNothing);

      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      _expectNoException(tester);
      expect(find.text('Today'), findsNothing);
    });

    testWidgets('Week adds a weekly class right in the day at $size', (
      tester,
    ) async {
      final repository = await _pumpSchedule(tester, size);

      // Past days offer no "Add class", so the first one is today's.
      await tester.ensureVisible(find.byTooltip('Add class').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add class').first);
      await tester.pumpAndSettle();
      _expectNoException(tester);
      expect(find.byType(AppSidePanel), findsOneWidget);
      expect(find.text('Create class'), findsOneWidget);

      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      _expectNoException(tester);

      await tester.ensureVisible(find.text('Trainer'));
      await tester.tap(find.text('Trainer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coach Alex').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Create'));
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      _expectNoException(tester);

      expect(find.byType(AppSidePanel), findsNothing);
      final draft = repository.lastCreatedTemplate;
      expect(draft, isNotNull);
      expect(draft!.weekdays, [DateTime.now().weekday]);
      expect(draft.classType, 'WOD');
    });

    testWidgets('A weekly session edits this date or its schedule at $size', (
      tester,
    ) async {
      await _pumpSchedule(tester, size);
      await _openTomorrowClass(tester);
      expect(find.byType(AppSidePanel), findsOneWidget);

      // Details edits this date; the link opens the weekly schedule.
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      _expectNoException(tester);
      expect(find.text('Changes apply to this class only.'), findsOneWidget);
      await tester.tap(find.text('Edit schedule'));
      await tester.pumpAndSettle();
      _expectNoException(tester);
      expect(find.byType(AppSidePanel), findsOneWidget);
      expect(find.text('Edit schedule'), findsOneWidget);
      expect(
        find.text(
          'Changes apply to all upcoming dates. Booked dates keep their time.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Add class opens the create panel at $size', (tester) async {
      await _pumpSchedule(tester, size);
      // Next week: every day is in the future, so both buttons exist.
      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byTooltip('Add class').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add class').first);
      await tester.pumpAndSettle();
      _expectNoException(tester);
      expect(find.byType(AppSidePanel), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AppSidePanel), findsNothing);

      // The header's + creates recurring classes.
      await tester.tap(find.byTooltip('Create recurring classes'));
      await tester.pumpAndSettle();
      _expectNoException(tester);
      expect(find.text('Create recurring classes'), findsOneWidget);
    });

    testWidgets('Owners remove a booked member at $size', (tester) async {
      final repository = await _pumpSchedule(
        tester,
        size,
        session: ScheduleClass(
          id: 10,
          gymId: 1,
          title: 'CrossFit',
          classType: 'WOD',
          startTime: _tomorrowAt(17).add(const Duration(minutes: 30)),
          durationMinutes: 60,
          capacity: 20,
          classTemplateId: 1,
          remainingSpots: 19,
          bookedCount: 1,
          bookings: const [
            ScheduleBooking(
              userId: 42,
              displayName: 'Clara Haas',
              nickname: 'clara',
              attendanceStatus: 'booked',
              isCurrentUser: false,
            ),
          ],
        ),
      );
      await _openTomorrowClass(tester);
      await tester.ensureVisible(find.byTooltip('Remove from class'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove from class'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      _expectNoException(tester);
      expect(repository.lastRemovedUserId, 42);
    });

    testWidgets('Athletes book a class from the week at $size', (tester) async {
      final repository = await _pumpSchedule(tester, size, profile: _athlete);
      expect(find.text('Add class'), findsNothing);
      expect(find.text('Add WOD'), findsNothing);
      expect(find.byTooltip('Import WODs'), findsNothing);

      await _openTomorrowClass(tester);
      await tester.ensureVisible(find.text('Book Class'));
      await tester.tap(find.text('Book Class'));
      await tester.pumpAndSettle();
      _expectNoException(tester);
      expect(repository.lastBookedClassId, _seriesSession.id);
      // Athletes get no Details tab.
      expect(find.text('Details'), findsNothing);
    });
  }
}
