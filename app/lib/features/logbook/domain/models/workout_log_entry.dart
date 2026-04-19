class WorkoutLogEntry {
  const WorkoutLogEntry({
    required this.id,
    required this.dailyWorkoutId,
    required this.classScheduleId,
    required this.scheduledDate,
    required this.workoutTitle,
    required this.classTitle,
    required this.classStartTime,
    required this.scoreType,
    required this.scoreValue,
    required this.scoreLabel,
    required this.notesText,
    required this.updatedAt,
    required this.isPr,
    required this.prRank,
  });

  final int id;
  final int dailyWorkoutId;
  final int? classScheduleId;
  final DateTime scheduledDate;
  final String workoutTitle;
  final String? classTitle;
  final DateTime? classStartTime;
  final String scoreType;
  final double scoreValue;
  final String scoreLabel;
  final String notesText;
  final DateTime updatedAt;
  final bool isPr;
  final int? prRank;
}
