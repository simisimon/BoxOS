class DailyWorkout {
  const DailyWorkout({
    required this.id,
    required this.gymId,
    required this.scheduledDate,
    required this.title,
    required this.strengthText,
    required this.metconText,
    required this.notesText,
    required this.canEdit,
    required this.whiteboardResults,
    required this.myWhiteboardResult,
    required this.myWorkoutLog,
  });

  final int id;
  final int gymId;
  final DateTime scheduledDate;
  final String title;
  final String strengthText;
  final String metconText;
  final String notesText;
  final bool canEdit;
  final List<WhiteboardResult> whiteboardResults;
  final WhiteboardResult? myWhiteboardResult;
  final WorkoutLogEntrySummary? myWorkoutLog;
}

class WorkoutLogEntrySummary {
  const WorkoutLogEntrySummary({
    required this.id,
    required this.scoreType,
    required this.scoreValue,
    required this.scoreLabel,
    required this.notesText,
    required this.updatedAt,
    required this.isPr,
    required this.prRank,
  });

  final int id;
  final String scoreType;
  final double scoreValue;
  final String scoreLabel;
  final String notesText;
  final DateTime updatedAt;
  final bool isPr;
  final int? prRank;
}

class WhiteboardResult {
  const WhiteboardResult({
    required this.id,
    required this.userId,
    required this.athleteName,
    required this.scoreType,
    required this.scoreValue,
    required this.scoreLabel,
    required this.notesText,
    required this.rank,
  });

  final int id;
  final int userId;
  final String athleteName;
  final String scoreType;
  final double scoreValue;
  final String scoreLabel;
  final String notesText;
  final int rank;
}
