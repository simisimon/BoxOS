import 'package:app/app.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:app/features/results/presentation/whiteboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(
  DateTime.now().year,
  DateTime.now().month,
  DateTime.now().day,
);

DailyWorkout _wod({DailyWorkoutStatus status = DailyWorkoutStatus.published}) =>
    DailyWorkout(
      id: 4,
      gymId: 1,
      scheduledDate: _today,
      title: 'Hero day',
      status: status,
      publishedAt: null,
      canEdit: false,
      sections: const [
        DailyWorkoutSection(
          id: 20,
          title: 'Warm Up',
          description: '500 m row',
          scoreType: WorkoutSectionScore.none,
        ),
        DailyWorkoutSection(
          id: 21,
          title: 'Metcon',
          description: '21-15-9 Thrusters, Pull-ups',
          scoreType: WorkoutSectionScore.time,
          memberNotes: 'Scale to 30 kg',
          coachNotes: 'Watch the lockout',
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<DailyWorkout> workouts,
  bool tv = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 1000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        programmingListProvider.overrideWith((ref) async => workouts),
        leaderboardProvider(4).overrideWith(
          (ref) async => {
            21: const [
              LeaderboardEntry(
                rank: 1,
                name: 'Ada',
                scoreLabel: '3:58',
                division: ResultDivision.rx,
              ),
              LeaderboardEntry(
                rank: 2,
                name: 'Ben',
                scoreLabel: '5:10',
                division: ResultDivision.scaled,
              ),
            ],
          },
        ),
      ],
      child: MaterialApp(
        theme: buildBoxOsTheme(),
        home: tv
            ? WhiteboardScreen(day: _today, tv: true)
            : Scaffold(body: WhiteboardScreen(day: _today)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the WOD and the scored blocks\' leaderboards', (
    tester,
  ) async {
    await _pump(tester, workouts: [_wod()]);
    expect(find.text('Hero day'), findsOneWidget);
    expect(find.text('Scale to 30 kg'), findsOneWidget);
    expect(find.text('Watch the lockout'), findsNothing);
    expect(find.text('2 results'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('5:10'), findsOneWidget);
    // Warm-ups have no leaderboard.
    expect(find.text('WARM UP'), findsOneWidget);
    expect(find.text('Warm Up'), findsNothing);
    expect(find.byTooltip('TV mode'), findsOneWidget);
    await tester.pump();
  });

  testWidgets('drafts stay off the whiteboard', (tester) async {
    await _pump(tester, workouts: [_wod(status: DailyWorkoutStatus.draft)]);
    expect(find.text('No WOD on the whiteboard for this day.'), findsOne);
    expect(find.text('Hero day'), findsNothing);
  });

  testWidgets('TV mode is full screen and can be left', (tester) async {
    await _pump(tester, workouts: [_wod()], tv: true);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byTooltip('Leave TV mode'), findsOneWidget);
    // Unmount so the refresh timer stops.
    await tester.pumpWidget(const SizedBox());
  });
}
