import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/calendar/domain/models/schedule_booking.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';

class ScheduleClass {
  const ScheduleClass({
    required this.id,
    required this.gymId,
    required this.title,
    required this.classType,
    required this.startTime,
    required this.durationMinutes,
    required this.capacity,
    this.classTemplateId,
    this.assignedTrainer,
    this.bookedCount = 0,
    this.remainingSpots = 0,
    this.waitlistCount = 0,
    this.isBooked = false,
    this.isWaitlisted = false,
    this.attendanceStatus,
    this.bookings = const [],
  });

  final int id;
  final int gymId;
  final String title;
  final String classType;
  final DateTime startTime;
  final int durationMinutes;
  final int capacity;

  /// The week-plan class this session was generated from; null for one-offs.
  final int? classTemplateId;
  final ScheduleTrainer? assignedTrainer;
  final int bookedCount;
  final int remainingSpots;
  final int waitlistCount;
  final bool isBooked;
  final bool isWaitlisted;
  final String? attendanceStatus;
  final List<ScheduleBooking> bookings;

  DateTime get endTime => startTime.add(Duration(minutes: durationMinutes));
  bool get isFull => remainingSpots <= 0;
  ClassType get type => ClassType.fromWire(classType);
}
