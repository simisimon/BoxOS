// Renders the Schedule (MyBox) month calendar with fake data and writes a PNG
// golden — used to preview the UI without a backend/login (the app itself
// can't be built on this machine without Windows Developer Mode/symlinks).
//
// Regenerate the screenshot with:
//   flutter test test/preview/schedule_preview_test.dart --update-goldens
import 'dart:io';

import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';
import 'package:app/features/calendar/domain/repositories/schedule_repository.dart';
import 'package:app/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/programming/domain/repositories/programming_repository.dart';
import 'package:app/features/programming/presentation/screens/import_workouts_dialog.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/gym_membership.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:app/features/profile/domain/models/user_profile.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _gym = GymSummary(
  id: 1,
  name: 'CrossFit Mitte',
  slug: 'crossfit-mitte',
  logoUrl: '',
  timezone: 'Europe/Berlin',
);

const _profile = UserProfile(
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

const _trainer = ScheduleTrainer(id: 7, displayName: 'Coach Alex', nickname: 'alex');

ScheduleClass _cls(int id, int day, int hour, String title) {
  final now = DateTime.now();
  return ScheduleClass(
    id: id,
    gymId: 1,
    title: title,
    classType: 'WOD',
    startTime: DateTime(now.year, now.month, day, hour),
    durationMinutes: 60,
    capacity: 12,
    assignedTrainer: _trainer,
    bookedCount: 6,
    remainingSpots: 6,
  );
}

List<ScheduleClass> _sampleClasses() => [
      _cls(1, 3, 6, 'Morning WOD'),
      _cls(2, 3, 18, 'Evening WOD'),
      _cls(3, 5, 9, 'Olympic Lifting'),
      _cls(4, 10, 7, 'Morning WOD'),
      _cls(5, 10, 12, 'Open Gym'),
      _cls(6, 10, 18, 'Evening WOD'),
      _cls(7, 12, 17, 'Gymnastics'),
      _cls(8, 16, 6, 'Morning WOD'),
      _cls(12, 16, 12, 'Open Gym'),
      _cls(13, 16, 18, 'Evening WOD'),
      _cls(9, 18, 19, 'Endurance'),
      _cls(10, 22, 10, 'Partner WOD'),
      _cls(11, 24, 18, 'Evening WOD'),
    ];

/// Offline stub so the inline form's trainer dropdown resolves instantly
/// instead of hitting the network (which would hang pumpAndSettle).
class _FakeScheduleRepository implements ScheduleRepository {
  @override
  Future<List<ScheduleClass>> fetchSchedule() async => _sampleClasses();

  @override
  Future<List<ScheduleTrainer>> fetchTrainers() async => const [_trainer];

  @override
  Future<ScheduleClass> createClass({
    required String title,
    required String classType,
    required DateTime startTime,
    required int durationMinutes,
    required int capacity,
    required int trainerUserId,
    String recurrenceFrequency = 'none',
    int occurrenceCount = 1,
  }) async => _cls(99, startTime.day, startTime.hour, title);

  @override
  Future<ScheduleClass> updateClass({
    required int id,
    required String title,
    required String classType,
    required DateTime startTime,
    required int durationMinutes,
    required int capacity,
    required int trainerUserId,
  }) async => _cls(id, startTime.day, startTime.hour, title);

  @override
  Future<void> deleteClass({required int id}) async {}

  @override
  Future<void> bookClass({required int classId}) async {}

  @override
  Future<void> cancelBooking({required int classId}) async {}

  @override
  Future<void> joinWaitlist({required int classId}) async {}

  @override
  Future<void> leaveWaitlist({required int classId}) async {}

  @override
  Future<ScheduleClass> updateAttendance({
    required int classId,
    required int userId,
    required String attendanceStatus,
  }) async => _cls(classId, 1, 6, 'WOD');
}

/// Offline stub for the bulk WOD import the schedule's upload button opens.
class _FakeProgrammingRepository implements ProgrammingRepository {
  @override
  Future<WorkoutImportResult> importWorkouts(
    List<Map<String, dynamic>> rows,
  ) async => WorkoutImportResult(createdCount: rows.length, errors: const []);

  @override
  Future<List<DailyWorkout>> fetchWorkouts() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<void> _loadRealFont() async {
  // Register a real TTF under 'Roboto' so golden text renders readably instead
  // of the test framework's box font.
  for (final path in [
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
      await loader.load();
      return;
    }
  }
}

void main() {
  testWidgets('Schedule month calendar preview', (tester) async {
    await _loadRealFont();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1120, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith((ref) async => _profile),
          scheduleRepositoryProvider.overrideWithValue(_FakeScheduleRepository()),
          scheduleListProvider.overrideWith((ref) async => _sampleClasses()),
          programmingRepositoryProvider.overrideWithValue(
            _FakeProgrammingRepository(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          home: const Scaffold(body: SafeArea(child: MyBoxScreen())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1) Full-width month calendar.
    await expectLater(
      find.byType(MyBoxScreen),
      matchesGoldenFile('goldens/schedule_month.png'),
    );

    // 2) Tap a future day with classes -> side panel opens next to the calendar.
    await tester.tap(find.text('16'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MyBoxScreen),
      matchesGoldenFile('goldens/schedule_day_panel.png'),
    );

    // 3) Tap "Add Class" -> inline create form in the panel.
    await tester.tap(find.text('Add Class'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MyBoxScreen),
      matchesGoldenFile('goldens/schedule_add_form.png'),
    );

    // 4) Tap a past day -> no "Add Class", a note explains why instead.
    await tester.tap(find.text('10').first);
    await tester.pumpAndSettle();
    expect(find.text('Add Class'), findsNothing);
    await expectLater(
      find.byType(MyBoxScreen),
      matchesGoldenFile('goldens/schedule_past_day.png'),
    );
  });

  testWidgets('Import button opens the import dialog', (tester) async {
    await _loadRealFont();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1120, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith((ref) async => _profile),
          scheduleRepositoryProvider.overrideWithValue(_FakeScheduleRepository()),
          scheduleListProvider.overrideWith((ref) async => _sampleClasses()),
          programmingRepositoryProvider.overrideWithValue(
            _FakeProgrammingRepository(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          home: const Scaffold(body: SafeArea(child: MyBoxScreen())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ImportWorkoutsDialog), findsNothing);
    await tester.tap(find.byIcon(Icons.upload_file_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(ImportWorkoutsDialog), findsOneWidget);

    // Paste valid rows and import — the dialog should close on success.
    await tester.enterText(
      find.byType(TextField),
      'date,title,section_1_description,section_1_score\n'
      '2099-06-20,Alpha,"500m row",time\n'
      '2099-06-21,Bravo,"Back Squat 5x5",weight',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import 2 WODs'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportWorkoutsDialog), findsNothing);
  });

  testWidgets('Import dialog preview', (tester) async {
    await _loadRealFont();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(620, 780);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Two valid rows and one rejected row, so the preview shows both states.
    const pasted =
        'date,title,status,section_1_title,section_1_description,section_1_score\n'
        '2099-06-20,Evening WOD,published,Strength,"Back Squat 5x5 @ 75%",weight\n'
        '2099-06-21,Morning WOD,draft,Warm Up,"500m row",time\n'
        '2099-06-22,Bad Row,published,Metcon,"21-15-9",stopwatch';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          programmingRepositoryProvider.overrideWithValue(
            _FakeProgrammingRepository(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          home: const Scaffold(
            backgroundColor: Color(0xFF0E0E12),
            body: Center(
              child: ImportWorkoutsDialog(debugInitialText: pasted),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ImportWorkoutsDialog),
      matchesGoldenFile('goldens/wod_import_dialog.png'),
    );
  });
}
