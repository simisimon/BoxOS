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
    this.reactionCount = 0,
    this.reactions = const {},
    this.myReaction,
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
  /// Total number of reactions across all kinds.
  final int reactionCount;
  /// Per-kind tallies, e.g. `{ 'fire': 4, 'clap': 2 }`. Kinds with zero are
  /// omitted by the backend.
  final Map<String, int> reactions;
  /// The current viewer's reaction kind, or null if they haven't reacted.
  final String? myReaction;

  WorkoutLogEntry copyWithReactions({
    required int reactionCount,
    required Map<String, int> reactions,
    required String? myReaction,
  }) {
    return WorkoutLogEntry(
      id: id,
      dailyWorkoutId: dailyWorkoutId,
      classScheduleId: classScheduleId,
      scheduledDate: scheduledDate,
      workoutTitle: workoutTitle,
      classTitle: classTitle,
      classStartTime: classStartTime,
      scoreType: scoreType,
      scoreValue: scoreValue,
      scoreLabel: scoreLabel,
      notesText: notesText,
      updatedAt: updatedAt,
      isPr: isPr,
      prRank: prRank,
      reactionCount: reactionCount,
      reactions: reactions,
      myReaction: myReaction,
    );
  }
}

/// Lightweight summary returned by the reactions endpoints; lets the UI patch
/// a card in place without a full refetch.
class WorkoutLogReactionSummary {
  const WorkoutLogReactionSummary({
    required this.reactionCount,
    required this.reactions,
    required this.myReaction,
  });

  final int reactionCount;
  final Map<String, int> reactions;
  final String? myReaction;
}
