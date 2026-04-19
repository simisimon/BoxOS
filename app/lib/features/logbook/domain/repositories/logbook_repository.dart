import 'package:app/features/logbook/domain/models/workout_log_entry.dart';

abstract class LogbookRepository {
  Future<List<WorkoutLogEntry>> fetchEntries();

  Future<WorkoutLogEntry> submitEntry({
    required int workoutId,
    required String scoreType,
    required String scoreValue,
    required String notesText,
  });
}
