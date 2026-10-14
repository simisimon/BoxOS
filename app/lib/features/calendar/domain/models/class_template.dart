import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';

/// A weekly class ("CrossFit, Mon–Fri 06:00") set up once in the week plan.
/// The backend turns it into concrete bookable [ScheduleClass] sessions.
class ClassTemplate {
  const ClassTemplate({
    required this.id,
    required this.title,
    required this.classType,
    required this.weekdays,
    required this.hour,
    required this.minute,
    required this.durationMinutes,
    required this.capacity,
    this.assignedTrainer,
  });

  final int id;
  final String title;
  final ClassType classType;

  /// ISO weekdays, 1 = Monday … 7 = Sunday (same as [DateTime.weekday]).
  final List<int> weekdays;

  /// Wall-clock start in the gym's timezone.
  final int hour;
  final int minute;
  final int durationMinutes;
  final int capacity;
  final ScheduleTrainer? assignedTrainer;

  String get startLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
