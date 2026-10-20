import 'package:app/features/programming/domain/models/daily_workout.dart';

/// A single rejected row from a bulk WOD import (1-based row number).
class WorkoutImportError {
  const WorkoutImportError({required this.row, required this.message});

  final int row;
  final String message;
}

/// Outcome of a bulk WOD import. The import is atomic on the backend: either
/// every row is created ([errors] empty) or none are ([createdCount] == 0).
class WorkoutImportResult {
  const WorkoutImportResult({required this.createdCount, required this.errors});

  final int createdCount;
  final List<WorkoutImportError> errors;

  bool get hasErrors => errors.isNotEmpty;
}

abstract class ProgrammingRepository {
  Future<List<DailyWorkout>> fetchWorkouts();

  /// Bulk-creates WODs from already-parsed [rows] (each a JSON map matching
  /// the import endpoint's schema).
  Future<WorkoutImportResult> importWorkouts(List<Map<String, dynamic>> rows);

  Future<DailyWorkout> createWorkout({
    required DateTime scheduledDate,
    required String title,
    required List<DailyWorkoutSection> sections,
    required DailyWorkoutStatus status,
  });

  Future<DailyWorkout> updateWorkout({
    required int id,
    required DateTime scheduledDate,
    required String title,
    required List<DailyWorkoutSection> sections,
  });

  Future<DailyWorkout> publishWorkout({required int id});

  Future<DailyWorkout> unpublishWorkout({required int id});

  Future<DailyWorkout> duplicateWorkout({
    required DateTime sourceDate,
    required DateTime targetDate,
  });
}
