import 'package:app/app.dart';
import 'package:app/features/calendar/domain/models/schedule_booking.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/data/movements_admin_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:app/features/results/presentation/block_results_panel.dart';
import 'package:app/features/results/presentation/movements_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdmin implements MovementsAdmin {
  var movements = [
    const GymMovement(id: 1, name: 'Bak Squat', blockCount: 2, resultCount: 5),
  ];
  final renamed = <int, String>{};
  final merged = <int, int>{};

  @override
  Future<List<GymMovement>> fetchGymMovements() async => movements;

  @override
  Future<List<GymMovement>> search(String query) async => const [
    GymMovement(id: 1, name: 'Bak Squat'),
    GymMovement(id: 7, name: 'Back Squat', builtIn: true),
  ];

  @override
  Future<GymMovement> update(int id, {String? name, bool? archived}) async {
    if (name != null) renamed[id] = name;
    movements = [GymMovement(id: id, name: name ?? 'Bak Squat')];
    return movements.single;
  }

  @override
  Future<GymMovement> merge(int id, {required int intoId}) async {
    merged[id] = intoId;
    movements = [];
    return const GymMovement(id: 7, name: 'Back Squat', builtIn: true);
  }
}

Widget _app(List overrides, Widget child) => ProviderScope(
  overrides: [...overrides],
  child: MaterialApp(
    theme: buildBoxOsTheme(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets('owner renames and merges a movement', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    final fake = _FakeAdmin();
    await tester.pumpWidget(
      _app([
        movementsAdminProvider.overrideWithValue(fake),
      ], const MovementsSettings()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bak Squat'), findsOneWidget);

    await tester.tap(find.byTooltip('Actions for Bak Squat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('movement-name')),
      'Box Squat',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fake.renamed, {1: 'Box Squat'});
    expect(find.text('Box Squat'), findsOneWidget);

    await tester.tap(find.byTooltip('Actions for Box Squat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge into…'));
    await tester.pumpAndSettle();
    // The movement itself is not offered as a target.
    expect(find.widgetWithText(RadioListTile<int>, 'Bak Squat'), findsNothing);
    await tester.tap(find.text('Back Squat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Merge').last);
    await tester.pumpAndSettle();
    expect(fake.merged, {1: 7});
    expect(find.text('Your box has not added any movements yet.'), findsOne);
    await tester.pump();
  });

  testWidgets('class results list every booked member per block', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    final workout = DailyWorkout(
      id: 3,
      gymId: 1,
      scheduledDate: DateTime(2026, 11, 14),
      title: 'WOD',
      status: DailyWorkoutStatus.published,
      publishedAt: null,
      canEdit: true,
      sections: const [
        DailyWorkoutSection(
          id: 10,
          title: 'Warm Up',
          description: 'Row',
          scoreType: WorkoutSectionScore.none,
        ),
        DailyWorkoutSection(
          id: 11,
          title: 'Metcon',
          description: 'Fran',
          scoreType: WorkoutSectionScore.time,
        ),
      ],
    );
    await tester.pumpWidget(
      _app(
        [
          leaderboardProvider(3).overrideWith(
            (ref) async => {
              11: const [
                LeaderboardEntry(
                  rank: 1,
                  userId: 5,
                  name: 'Ada',
                  scoreLabel: '4:12',
                  division: ResultDivision.rx,
                  isPr: true,
                ),
              ],
            },
          ),
        ],
        ClassResults(
          workout: workout,
          bookings: const [
            ScheduleBooking(
              userId: 5,
              displayName: 'Ada',
              nickname: '',
              attendanceStatus: 'attended',
              isCurrentUser: false,
            ),
            ScheduleBooking(
              userId: 6,
              displayName: 'Ben',
              nickname: '',
              attendanceStatus: 'booked',
              isCurrentUser: false,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Warm Up'), findsNothing);
    expect(find.text('Metcon'), findsNWidgets(2));
    expect(find.text('4:12 · Rx · PR'), findsOneWidget);
    expect(find.text('No result'), findsOneWidget);
  });
}
