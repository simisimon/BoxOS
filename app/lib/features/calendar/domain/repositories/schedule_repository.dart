import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';

/// A single rejected row from a bulk class import (1-based row number).
class ScheduleImportError {
  const ScheduleImportError({required this.row, required this.message});

  final int row;
  final String message;
}

/// Outcome of a bulk class import. The import is atomic on the backend: either
/// every row is created ([errors] empty) or none are ([createdCount] == 0).
class ScheduleImportResult {
  const ScheduleImportResult({
    required this.createdCount,
    required this.errors,
  });

  final int createdCount;
  final List<ScheduleImportError> errors;

  bool get hasErrors => errors.isNotEmpty;
}

abstract class ScheduleRepository {
  Future<List<ScheduleClass>> fetchSchedule();
  Future<List<ScheduleTrainer>> fetchTrainers();

  /// Bulk-creates classes from already-parsed [rows] (each a JSON map matching
  /// the import endpoint's schema).
  Future<ScheduleImportResult> importClasses(List<Map<String, dynamic>> rows);

  Future<ScheduleClass> createClass({
    required String title,
    required String classType,
    required DateTime startTime,
    required int durationMinutes,
    required int capacity,
    required int trainerUserId,
    required String wodDescription,
    String recurrenceFrequency = 'none',
    int occurrenceCount = 1,
  });

  Future<ScheduleClass> updateClass({
    required int id,
    required String title,
    required String classType,
    required DateTime startTime,
    required int durationMinutes,
    required int capacity,
    required int trainerUserId,
    required String wodDescription,
  });

  Future<void> deleteClass({required int id});

  Future<void> bookClass({required int classId});

  Future<void> cancelBooking({required int classId});

  Future<void> joinWaitlist({required int classId});

  Future<void> leaveWaitlist({required int classId});

  Future<ScheduleClass> updateAttendance({
    required int classId,
    required int userId,
    required String attendanceStatus,
  });
}
