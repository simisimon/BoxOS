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

/// A program block (docs/admin-ui-reference.md §3.1): free-text workout or a
/// structured exercise.
enum BlockKind { workout, exercise }

/// What a set's value means: percent of 1RM or RPE.
enum SetUnit { percent, rpe }

/// One numbered set of an exercise block: [reps] reps @ [value] (% or RPE);
/// [value] is null when only reps are prescribed.
class WorkoutSet {
  const WorkoutSet({required this.reps, this.value});

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
    reps: (json['reps'] as num? ?? 1).toInt(),
    value: (json['value'] as num?)?.toDouble(),
  );

  final int reps;
  final double? value;

  Map<String, dynamic> toJson() => {'reps': reps, 'value': value};

  @override
  bool operator ==(Object other) =>
      other is WorkoutSet && other.reps == reps && other.value == value;

  @override
  int get hashCode => Object.hash(reps, value);
}

class DailyWorkoutSection {
  const DailyWorkoutSection({
    required this.title,
    required this.description,
    required this.scoreType,
    this.kind = BlockKind.workout,
    this.exerciseName = '',
    this.setUnit = SetUnit.percent,
    this.sets = const [],
    this.coachNotes = '',
    this.memberNotes = '',
  });

  factory DailyWorkoutSection.fromJson(Map<String, dynamic> json) =>
      DailyWorkoutSection(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        scoreType: parseWorkoutSectionScore(json['score_type']),
        kind: json['kind'] == 'exercise'
            ? BlockKind.exercise
            : BlockKind.workout,
        exerciseName: json['exercise_name'] as String? ?? '',
        setUnit: json['set_unit'] == 'rpe' ? SetUnit.rpe : SetUnit.percent,
        sets: [
          for (final raw in json['sets'] as List? ?? const [])
            WorkoutSet.fromJson(raw as Map<String, dynamic>),
        ],
        coachNotes: json['coach_notes'] as String? ?? '',
        memberNotes: json['member_notes'] as String? ?? '',
      );

  final String title;

  /// Free text for workout blocks; for exercise blocks the readable version
  /// of the sets, so every reader (logbook, athletes) still has text.
  final String description;
  final WorkoutSectionScore scoreType;
  final BlockKind kind;
  final String exerciseName;
  final SetUnit setUnit;
  final List<WorkoutSet> sets;

  /// Only coaches see these; the server blanks them for members.
  final String coachNotes;

  /// Shown to members in the app.
  final String memberNotes;

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'score_type': workoutSectionScoreToWire(scoreType),
    'kind': kind.name,
    'exercise_name': exerciseName,
    'set_unit': setUnit.name,
    'sets': [for (final set in sets) set.toJson()],
    'coach_notes': coachNotes,
    'member_notes': memberNotes,
  };
}

/// `5 @ 80%` / `5 @ RPE 8` / `5 reps`.
String formatWorkoutSet(WorkoutSet set, SetUnit unit) {
  final value = set.value;
  if (value == null) return '${set.reps} reps';
  final number = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
  return unit == SetUnit.rpe
      ? '${set.reps} @ RPE $number'
      : '${set.reps} @ $number%';
}

/// Magic Set Builder: turns `5x5 @ 80%`, `3x3@85, 2x1@90` or `4x8 rpe 7` into
/// sets. Parts it cannot read are skipped; null when nothing was readable.
List<WorkoutSet>? parseSetShorthand(String text) {
  // A value is never the start of the next "NxM" part, so `3x3@85,2x1@90`
  // reads 85 (not 85.2) and `5x5 3x3` has no value.
  final pattern = RegExp(
    r'(\d+)\s*[x×]\s*(\d+)\s*(?:(?:@|at)\s*)?(?:rpe\s*)?'
    r'(?:(\d+(?:[.,]\d+)?)(?!\d*\s*[x×]))?\s*%?',
    caseSensitive: false,
  );
  final sets = <WorkoutSet>[];
  for (final match in pattern.allMatches(text)) {
    final count = int.parse(match.group(1)!);
    final reps = int.parse(match.group(2)!);
    final raw = match.group(3);
    final value = raw == null ? null : double.parse(raw.replaceAll(',', '.'));
    if (count < 1 || count > 30 || reps < 1 || reps > 999) continue;
    for (var i = 0; i < count; i++) {
      sets.add(WorkoutSet(reps: reps, value: value));
    }
  }
  return sets.isEmpty ? null : sets.take(30).toList();
}

/// Whether set shorthand speaks in RPE rather than percent.
bool shorthandUsesRpe(String text) =>
    RegExp(r'rpe', caseSensitive: false).hasMatch(text);

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
