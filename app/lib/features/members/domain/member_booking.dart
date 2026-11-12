import 'package:app/features/calendar/domain/models/class_type.dart';

/// One class a member booked or waits for, from
/// `GET /membership/members/{id}/bookings`.
class MemberBooking {
  const MemberBooking({
    required this.classId,
    required this.title,
    required this.type,
    required this.start,
    required this.end,
    required this.trainerName,
    required this.status,
  });

  factory MemberBooking.fromJson(Map<String, dynamic> json) => MemberBooking(
    classId: (json['class_id'] as num).toInt(),
    title: json['title'] as String? ?? '',
    type: ClassType.fromWire(json['class_type'] as String? ?? ''),
    start: DateTime.parse(json['start_time'] as String).toLocal(),
    end: DateTime.parse(json['end_time'] as String).toLocal(),
    trainerName: json['trainer_name'] as String? ?? '',
    status: json['status'] as String? ?? 'booked',
  );

  final int classId;
  final String title;
  final ClassType type;
  final DateTime start;
  final DateTime end;
  final String trainerName;

  /// `booked`, `attended`, `no_show` or `waitlist`.
  final String status;
}
