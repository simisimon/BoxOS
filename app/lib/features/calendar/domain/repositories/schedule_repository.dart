import 'package:app/features/calendar/domain/models/class_template.dart';
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
  });

  Future<void> deleteClass({required int id});

  Future<List<ClassTemplate>> fetchTemplates();

  Future<ClassTemplate> createTemplate(ClassTemplateDraft draft);

  /// Returns how many already-booked sessions were kept unchanged as one-offs
  /// because they no longer fit the edited plan.
  Future<int> updateTemplate({
    required int id,
    required ClassTemplateDraft draft,
  });

  /// Returns how many already-booked sessions were kept as one-offs.
  Future<int> deleteTemplate({required int id});

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

/// Form values for creating or editing a [ClassTemplate].
class ClassTemplateDraft {
  const ClassTemplateDraft({
    required this.title,
    required this.classType,
    required this.weekdays,
    required this.hour,
    required this.minute,
    required this.durationMinutes,
    required this.capacity,
    this.trainerUserId,
  });

  final String title;
  final String classType;
  final List<int> weekdays;
  final int hour;
  final int minute;
  final int durationMinutes;
  final int capacity;
  final int? trainerUserId;
}
