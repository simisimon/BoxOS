import 'package:app/app.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:app/features/results/presentation/log_result_panel.dart';
import 'package:app/features/results/presentation/my_results_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeResults implements ResultsRepository {
  final saved = <ResultDraft>[];
  final deleted = <int>[];

  @override
  Future<WorkoutResult> saveResult(ResultDraft draft) async {
    saved.add(draft);
    return WorkoutResult(
      id: 1,
      sectionId: draft.sectionId,
      performedOn: DateTime(2026, 11, 14),
      scoreLabel: draft.score ?? '',
      scoreValue: 0,
      division: draft.division,
    );
  }

  @override
  Future<void> deleteResult({required int sectionId}) async =>
      deleted.add(sectionId);

  ResultHistory history = const ResultHistory(results: []);

  @override
  Future<ResultHistory> fetchHistory(int sectionId) async => history;

  @override
  Future<Map<int, List<LeaderboardEntry>>> fetchLeaderboard(
    int workoutId,
  ) async => const {};

  @override
  Future<MyResults> fetchMyResults(ResultFilter? filter) async =>
      const MyResults(results: [], filters: []);

  @override
  Future<MyResults> fetchMemberResults(int userId, ResultFilter? filter) =>
      fetchMyResults(filter);

  ResultsVisibility visibility = ResultsVisibility.gym;

  @override
  Future<ResultsVisibility> fetchResultsPrivacy() async => visibility;

  @override
  Future<ResultsVisibility> saveResultsPrivacy(ResultsVisibility value) async =>
      visibility = value;

  @override
  Future<String> exportResultsCsv() async => 'date\n';

  MovementInfo? movement;

  @override
  Future<MovementInfo> fetchMovement(int movementId) async =>
      movement ?? MovementInfo(id: movementId, name: '');
}

Future<LogResultOutcome?> Function() _open(
  WidgetTester tester,
  _FakeResults fake,
  DailyWorkoutSection section,
) {
  LogResultOutcome? outcome;
  return () async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [resultsRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          theme: buildBoxOsTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => outcome = await showLogResultPanel(
                  context,
                  section: section,
                  dayLabel: 'Nov 14',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return outcome;
  };
}

void main() {
  testWidgets('logs a scaled time with notes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    final fake = _FakeResults();
    await _open(
      tester,
      fake,
      const DailyWorkoutSection(
        id: 7,
        title: 'Metcon',
        description: '21-15-9 Thrusters, Pull-ups',
        scoreType: WorkoutSectionScore.time,
      ),
    )();
    expect(find.text('Log result'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('result-score')), '4:12');
    await tester.tap(find.text('Scaled'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes (optional)'),
      'Banded pull-ups',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(fake.saved.single.toJson(), {
      'section_id': 7,
      'score': '4:12',
      'division': 'scaled',
      'time_capped': false,
      'notes': 'Banded pull-ups',
    });
  });

  testWidgets('rounds and reps are joined, empty reps count as 0', (
    tester,
  ) async {
    final fake = _FakeResults();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await _open(
      tester,
      fake,
      const DailyWorkoutSection(
        id: 8,
        title: 'Cindy',
        description: '20 min AMRAP',
        scoreType: WorkoutSectionScore.roundsReps,
      ),
    )();
    await tester.enterText(find.byKey(const ValueKey('result-score')), '17');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(fake.saved.single.score, '17+0');
  });

  testWidgets('exercise blocks log the prescribed sets with weights', (
    tester,
  ) async {
    final fake = _FakeResults();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await _open(
      tester,
      fake,
      const DailyWorkoutSection(
        id: 9,
        title: 'Back Squat',
        description: 'Back Squat',
        scoreType: WorkoutSectionScore.weight,
        kind: BlockKind.exercise,
        exerciseName: 'Back Squat',
        sets: [WorkoutSet(reps: 5, value: 75), WorkoutSet(reps: 3, value: 85)],
      ),
    )();
    // Without a weight the result is refused here.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the weight of at least one set.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('result-set-kg-0')), '90');
    await tester.enterText(
      find.byKey(const ValueKey('result-set-kg-1')),
      '102,5',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump();
    final sets = fake.saved.single.sets!;
    expect([for (final s in sets) s.reps], [5, 3]);
    expect([for (final s in sets) s.kg], [90, 102.5]);
  });

  testWidgets('an existing result can be deleted', (tester) async {
    final fake = _FakeResults();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await _open(
      tester,
      fake,
      DailyWorkoutSection(
        id: 10,
        title: 'Max reps',
        description: 'Max pull-ups',
        scoreType: WorkoutSectionScore.reps,
        myResult: WorkoutResult(
          id: 3,
          sectionId: 10,
          performedOn: DateTime(2026, 11, 13),
          scoreLabel: '25 reps',
          scoreValue: 25,
          division: ResultDivision.rx,
        ),
      ),
    )();
    expect(find.text('Edit result'), findsOneWidget);
    expect(find.widgetWithText(TextField, '25'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(fake.deleted, [10]);
  });

  testWidgets('shows last times and suggests kg from the estimated 1RM', (
    tester,
  ) async {
    final fake = _FakeResults()
      ..history = ResultHistory(
        results: [
          WorkoutResult(
            id: 4,
            sectionId: 2,
            performedOn: DateTime(2026, 10, 1),
            scoreLabel: '100 kg',
            scoreValue: 100,
            division: ResultDivision.rx,
            isPr: true,
          ),
        ],
        bestSets: const [BestSet(reps: 1, kg: 100)],
      );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await _open(
      tester,
      fake,
      const DailyWorkoutSection(
        id: 11,
        title: 'Back Squat',
        description: 'Back Squat',
        scoreType: WorkoutSectionScore.weight,
        kind: BlockKind.exercise,
        exerciseName: 'Back Squat',
        sets: [WorkoutSet(reps: 5, value: 75)],
      ),
    )();
    expect(find.text('LAST TIMES'), findsOneWidget);
    expect(find.text('PR'), findsOneWidget);
    expect(find.text('75'), findsOneWidget); // 75 % of 100 kg as the hint
    await tester.pump();
  });

  testWidgets('exercise blocks fold in the movement how-to', (tester) async {
    final fake = _FakeResults()
      ..movement = const MovementInfo(
        id: 3,
        name: 'Back Squat',
        instructions: ['Bar on your back.', 'Sit down, stand up.'],
        primaryMuscles: ['quadriceps'],
      );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await _open(
      tester,
      fake,
      const DailyWorkoutSection(
        id: 9,
        title: 'Strength',
        description: 'Back Squat 5x5',
        scoreType: WorkoutSectionScore.weight,
        kind: BlockKind.exercise,
        exerciseName: 'Back Squat',
        movementId: 3,
      ),
    )();
    expect(find.text('How to: Back Squat'), findsOneWidget);
    expect(find.text('1. Bar on your back.'), findsNothing);
    await tester.tap(find.text('How to: Back Squat'));
    await tester.pumpAndSettle();
    expect(find.text('1. Bar on your back.'), findsOneWidget);
    expect(find.text('Muscles: quadriceps'), findsOneWidget);
    await tester.pump();
  });

  testWidgets('results privacy can be set to only me', (tester) async {
    final fake = _FakeResults();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [resultsRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp(
          theme: buildBoxOsTheme(),
          home: const Scaffold(body: ResultsPrivacyCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('My gym'), findsOneWidget);
    await tester.tap(find.text('My gym'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only me and my coaches').last);
    await tester.pumpAndSettle();
    expect(fake.visibility, ResultsVisibility.private);
    expect(find.textContaining('Your coaches still do.'), findsOneWidget);
  });
}
