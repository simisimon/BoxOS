import 'package:app/features/logbook/domain/models/workout_log_entry.dart';

abstract class LogbookRepository {
  Future<List<WorkoutLogEntry>> fetchEntries();

  Future<WorkoutLogEntry> submitEntry({
    required int workoutId,
    required String scoreType,
    required String scoreValue,
    required String notesText,
  });

  /// Sets (or replaces) the viewer's reaction on a workout log. Returns the
  /// updated aggregate summary so the UI can patch the card in place.
  Future<WorkoutLogReactionSummary> setReaction({
    required int entryId,
    required String reaction,
  });

  /// Clears the viewer's reaction on the workout log, if any.
  Future<WorkoutLogReactionSummary> clearReaction({required int entryId});
}
