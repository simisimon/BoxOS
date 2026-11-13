import 'package:app/app.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/presentation/widgets/schedule_week_view.dart'
    show mondayOf;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/calendar/presentation/widgets/schedule_hour_grid.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleClass _class(int id, int hour, int minute, int minutes) =>
    ScheduleClass(
      id: id,
      gymId: 1,
      title: 'C$id',
      classType: 'WOD',
      startTime: DateTime(2026, 11, 12, hour, minute),
      durationMinutes: minutes,
      capacity: 10,
      remainingSpots: 10,
    );

void main() {
  test('overlapping classes share lanes, a lone class keeps full width', () {
    final placed = {
      for (final p in laneLayout([
        _class(1, 6, 0, 60),
        _class(2, 6, 30, 60), // overlaps 1
        _class(3, 7, 0, 60), // starts when 1 ends: reuses lane 0
        _class(4, 12, 0, 60), // alone
      ]))
        p.session.id: (p.lane, p.laneCount),
    };
    expect(placed[1], (0, 2));
    expect(placed[2], (1, 2));
    expect(placed[3], (0, 2));
    expect(placed[4], (0, 1));
  });

  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    testWidgets('a late class stays on the grid and opens at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final monday = mondayOf(DateTime.now());
      ScheduleClass? opened;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleListProvider.overrideWith(
              (ref) async => [
                ScheduleClass(
                  id: 9,
                  gymId: 1,
                  title: 'Late Open Gym',
                  classType: 'Open Gym',
                  // Ends at midnight: the grid must reach 24:00.
                  startTime: DateTime(
                    monday.year,
                    monday.month,
                    monday.day,
                    23,
                  ),
                  durationMinutes: 60,
                  capacity: 10,
                  remainingSpots: 10,
                ),
              ],
            ),
          ],
          child: MaterialApp(
            theme: buildBoxOsTheme(),
            home: Scaffold(
              body: ScheduleHourGrid(
                weekStart: monday,
                onWeekChanged: (_) {},
                onOpenClass: (c) => opened = c,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Late Open Gym'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Late Open Gym'));
      expect(opened?.id, 9);
      expect(tester.takeException(), isNull);
    });
  }
}
