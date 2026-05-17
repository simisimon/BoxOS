import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';

abstract class ScheduleRepository {
  Future<List<ScheduleClass>> fetchSchedule();
  Future<List<ScheduleTrainer>> fetchTrainers();

  Future<ScheduleClass> createClass({
    required String title,
    required String classType,
    required DateTime startTime,
    required int durationMinutes,
    required int capacity,
    required int trainerUserId,
    required String wodDescription,
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
