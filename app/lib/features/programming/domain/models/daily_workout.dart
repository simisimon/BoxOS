enum DailyWorkoutStatus { draft, published }

DailyWorkoutStatus parseDailyWorkoutStatus(Object? value) {
  return value == 'published'
      ? DailyWorkoutStatus.published
      : DailyWorkoutStatus.draft;
}

String dailyWorkoutStatusToWire(DailyWorkoutStatus status) {
  return status == DailyWorkoutStatus.published ? 'published' : 'draft';
}

/// Score unit a coach assigns to a WOD section. Matches the backend's
/// `time` / `rounds_reps` / `weight` vocabulary.
enum WorkoutSectionScore { time, roundsReps, weight }

WorkoutSectionScore parseWorkoutSectionScore(Object? value) {
  switch (value) {
    case 'time':
      return WorkoutSectionScore.time;
    case 'rounds_reps':
      return WorkoutSectionScore.roundsReps;
    case 'weight':
      return WorkoutSectionScore.weight;
    default:
      return WorkoutSectionScore.time;
  }
}

String workoutSectionScoreToWire(WorkoutSectionScore score) {
  switch (score) {
    case WorkoutSectionScore.time:
      return 'time';
    case WorkoutSectionScore.roundsReps:
      return 'rounds_reps';
    case WorkoutSectionScore.weight:
      return 'weight';
  }
}

String workoutSectionScoreLabel(WorkoutSectionScore score) {
  switch (score) {
    case WorkoutSectionScore.time:
      return 'Time';
    case WorkoutSectionScore.roundsReps:
      return 'Rounds + Reps';
    case WorkoutSectionScore.weight:
      return 'Weight (kg)';
  }
}

class DailyWorkoutSection {
  const DailyWorkoutSection({
    required this.title,
    required this.description,
    required this.scoreType,
  });

  final String title;
  final String description;
  final WorkoutSectionScore scoreType;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'score_type': workoutSectionScoreToWire(scoreType),
  };
}

class DailyWorkout {
  const DailyWorkout({
    required this.id,
    required this.gymId,
    required this.scheduledDate,
    required this.title,
    required this.sections,
    required this.status,
    required this.publishedAt,
    required this.canEdit,
    required this.whiteboardResults,
    required this.myWhiteboardResult,
    required this.myWorkoutLog,
  });

  final int id;
  final int gymId;
  final DateTime scheduledDate;
  final String title;
  final List<DailyWorkoutSection> sections;
  final DailyWorkoutStatus status;
  final DateTime? publishedAt;
  final bool canEdit;
  final List<WhiteboardResult> whiteboardResults;
  final WhiteboardResult? myWhiteboardResult;
  final WorkoutLogEntrySummary? myWorkoutLog;

  bool get isPublished => status == DailyWorkoutStatus.published;
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
