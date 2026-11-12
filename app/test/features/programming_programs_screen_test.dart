import 'package:app/app.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/programming/domain/repositories/programming_repository.dart';
import 'package:app/features/programming/presentation/screens/programs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProgramming implements ProgrammingRepository {
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

void main() {
  for (final size in const [Size(1440, 900), Size(390, 844)]) {
    testWidgets('board shows the week and edits in a panel at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            programmingRepositoryProvider.overrideWithValue(_FakeProgramming()),
          ],
          child: MaterialApp(
            theme: buildBoxOsTheme(),
            home: const Scaffold(body: ProgramsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Metcon'), findsOneWidget);
      expect(find.text('PUBLISHED'), findsOneWidget);

      // Next week is all future: every column offers "Add block".
      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();
      expect(find.text('Metcon'), findsNothing);
      await tester.tap(find.text('Add block').first);
      await tester.pumpAndSettle();
      expect(find.byType(AppSidePanel), findsOneWidget);
      expect(find.text('New block'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
