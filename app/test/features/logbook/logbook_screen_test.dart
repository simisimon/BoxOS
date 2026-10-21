import 'package:app/app.dart';
import 'package:app/features/logbook/data/repositories/api_logbook_repository.dart';
import 'package:app/features/logbook/domain/models/workout_log_entry.dart';
import 'package:app/features/logbook/domain/repositories/logbook_repository.dart';
import 'package:app/features/logbook/presentation/screens/logbook_screen.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/gym_membership.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:app/features/profile/domain/models/user_profile.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
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

class _FakeLogbookRepository implements LogbookRepository {
  @override
  Future<List<WorkoutLogEntry>> fetchEntries() async => [
    WorkoutLogEntry(
      id: 1,
      dailyWorkoutId: 7,
      classScheduleId: null,
      scheduledDate: DateTime(2026, 10, 12),
      workoutTitle: 'Fran',
      classTitle: 'CrossFit',
      classStartTime: null,
      scoreType: 'time',
      scoreValue: 248,
      scoreLabel: '4:08',
      notesText: 'Unbroken thrusters',
      updatedAt: DateTime(2026, 10, 12),
      isPr: true,
      prRank: 1,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  testWidgets('logbook shows logged WODs with score and movements only', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith((ref) async => _athlete),
          logbookRepositoryProvider.overrideWithValue(_FakeLogbookRepository()),
          programmingListProvider.overrideWith(
            (ref) async => [
              DailyWorkout(
                id: 7,
                gymId: 1,
                scheduledDate: DateTime(2026, 10, 12),
                title: 'Fran',
                sections: const [
                  DailyWorkoutSection(
                    title: 'Strength',
                    description: 'Back Squat 5-5-3-3-1',
                    scoreType: WorkoutSectionScore.weight,
                  ),
                  DailyWorkoutSection(
                    title: 'Metcon',
                    description: '21-15-9 Thrusters + Pull-ups',
                    scoreType: WorkoutSectionScore.time,
                  ),
                ],
                status: DailyWorkoutStatus.published,
                publishedAt: null,
                canEdit: false,
                myWorkoutLog: null,
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: buildBoxOsTheme(),
          home: const Scaffold(body: LogbookScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fran'), findsOneWidget);
    expect(find.text('4:08'), findsOneWidget);
    expect(find.text('PR'), findsOneWidget);
    expect(find.text('Strength — Back Squat 5-5-3-3-1'), findsOneWidget);
    expect(find.text('Metcon — 21-15-9 Thrusters + Pull-ups'), findsOneWidget);
    expect(find.text('Unbroken thrusters'), findsOneWidget);

    // History only: no tracking, no workout builder.
    expect(find.text('Track a workout'), findsNothing);
    expect(find.text('Create workout'), findsNothing);
    expect(find.text('My workouts'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
