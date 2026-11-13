import 'package:app/app.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/programming/presentation/widgets/block_editor_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Magic Set Builder reads common shorthand', () {
    expect(parseSetShorthand('5x5 @ 80%'), [
      for (var i = 0; i < 5; i++) const WorkoutSet(reps: 5, value: 80),
    ]);
    expect(parseSetShorthand('3x3@85, 2x1@90'), [
      for (var i = 0; i < 3; i++) const WorkoutSet(reps: 3, value: 85),
      for (var i = 0; i < 2; i++) const WorkoutSet(reps: 1, value: 90),
    ]);
    expect(parseSetShorthand('4x8 rpe 7.5'), [
      for (var i = 0; i < 4; i++) const WorkoutSet(reps: 8, value: 7.5),
    ]);
    expect(parseSetShorthand('3x10'), [
      for (var i = 0; i < 3; i++) const WorkoutSet(reps: 10),
    ]);
    // No space after the comma: still two parts, not 85.2.
    expect(parseSetShorthand('3x3@85,2x1@90'), [
      for (var i = 0; i < 3; i++) const WorkoutSet(reps: 3, value: 85),
      for (var i = 0; i < 2; i++) const WorkoutSet(reps: 1, value: 90),
    ]);
    // A following part's number is not this part's value.
    expect(parseSetShorthand('5x5 3x3'), [
      for (var i = 0; i < 5; i++) const WorkoutSet(reps: 5),
      for (var i = 0; i < 3; i++) const WorkoutSet(reps: 3),
    ]);
    expect(parseSetShorthand('3x3 @ 82,5%'), [
      for (var i = 0; i < 3; i++) const WorkoutSet(reps: 3, value: 82.5),
    ]);
    expect(shorthandUsesRpe('4x8 RPE 7'), isTrue);
    expect(parseSetShorthand('heavy single'), isNull);
  });

  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    testWidgets('exercise block from the Magic Set Builder at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      DailyWorkoutSection? saved;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildBoxOsTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => saved = await showBlockEditorPanel(
                    context,
                    dayLabel: 'Monday',
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

      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Exercise name'),
        'Back Squat',
      );
      await tester.tap(find.text('Try the Magic Set Builder'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Magic Set Builder'),
        '3x5 @ 80%',
      );
      await tester.tap(find.text('Build sets'));
      await tester.pumpAndSettle();
      // Three set rows plus the always-empty one.
      expect(find.text('4.'), findsOneWidget);

      await tester.tap(find.text('Member notes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Member notes'),
        'Belt allowed',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved?.kind, BlockKind.exercise);
      expect(saved?.title, 'Back Squat');
      expect(saved?.sets, [
        for (var i = 0; i < 3; i++) const WorkoutSet(reps: 5, value: 80),
      ]);
      expect(saved?.memberNotes, 'Belt allowed');
      expect(saved?.description, contains('1. 5 @ 80%'));
      expect(tester.takeException(), isNull);
    });
  }
}
