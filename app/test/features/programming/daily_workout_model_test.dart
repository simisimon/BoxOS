import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a saved block sends its id and named workout back', () {
    final section = DailyWorkoutSection.fromJson({
      'id': 42,
      'title': 'Metcon',
      'description': '21-15-9',
      'score_type': 'calories',
      'workout_name': 'Fran',
      'movement_id': null,
    });
    expect(section.scoreType, WorkoutSectionScore.calories);
    final json = section.toJson();
    expect(json['id'], 42);
    expect(json['score_type'], 'calories');
    expect(json['workout_name'], 'Fran');
  });

  test('a new block sends no id', () {
    const section = DailyWorkoutSection(
      title: 'Warm Up',
      description: 'Row',
      scoreType: WorkoutSectionScore.none,
    );
    expect(section.toJson().containsKey('id'), isFalse);
    expect(section.isScored, isFalse);
  });

  test('every score type round-trips', () {
    for (final score in WorkoutSectionScore.values) {
      expect(
        parseWorkoutSectionScore(workoutSectionScoreToWire(score)),
        score,
      );
    }
  });

  test('warm-up names are recognised', () {
    expect(looksLikeWarmUp('Warm Up'), isTrue);
    expect(looksLikeWarmUp('warm-up'), isTrue);
    expect(looksLikeWarmUp('Metcon'), isFalse);
  });
}
