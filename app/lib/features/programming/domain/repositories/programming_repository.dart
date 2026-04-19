import 'package:app/features/programming/domain/models/daily_workout.dart';

abstract class ProgrammingRepository {
  Future<List<DailyWorkout>> fetchWorkouts();

  Future<DailyWorkout> createWorkout({
    required DateTime scheduledDate,
    required String title,
    required String strengthText,
    required String metconText,
    required String notesText,
  });

  Future<DailyWorkout> updateWorkout({
    required int id,
    required DateTime scheduledDate,
    required String title,
    required String strengthText,
    required String metconText,
    required String notesText,
  });

  Future<DailyWorkout> submitWhiteboardResult({
    required int workoutId,
    required String scoreType,
    required String scoreValue,
    required String notesText,
  });
}
