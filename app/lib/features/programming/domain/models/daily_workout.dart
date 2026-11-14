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
/// `time` / `rounds_reps` / `reps` / `weight` / `calories` / `distance` /
/// `none` vocabulary; `none` blocks (warm-up, accessory) take no result.
enum WorkoutSectionScore {
  time,
  roundsReps,
  reps,
  weight,
  calories,
  distance,
  none,
}

const _scoreWire = {
  WorkoutSectionScore.time: 'time',
  WorkoutSectionScore.roundsReps: 'rounds_reps',
  WorkoutSectionScore.reps: 'reps',
  WorkoutSectionScore.weight: 'weight',
  WorkoutSectionScore.calories: 'calories',
  WorkoutSectionScore.distance: 'distance',
  WorkoutSectionScore.none: 'none',
};

WorkoutSectionScore parseWorkoutSectionScore(Object? value) {
  for (final entry in _scoreWire.entries) {
    if (entry.value == value) return entry.key;
  }
  return WorkoutSectionScore.time;
}

String workoutSectionScoreToWire(WorkoutSectionScore score) =>
    _scoreWire[score]!;

String workoutSectionScoreLabel(WorkoutSectionScore score) {
  switch (score) {
    case WorkoutSectionScore.time:
      return 'Time';
    case WorkoutSectionScore.roundsReps:
      return 'Rounds + Reps';
    case WorkoutSectionScore.reps:
      return 'Reps';
    case WorkoutSectionScore.weight:
      return 'Weight (kg)';
    case WorkoutSectionScore.calories:
      return 'Calories';
    case WorkoutSectionScore.distance:
      return 'Distance (m)';
    case WorkoutSectionScore.none:
      return 'No score';
  }
}

/// A block whose title says it is a warm-up gets no score by default.
bool looksLikeWarmUp(String title) =>
    RegExp(r'warm[\s-]?up', caseSensitive: false).hasMatch(title);

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
    this.id,
    required this.title,
    required this.description,
    required this.scoreType,
    this.kind = BlockKind.workout,
    this.exerciseName = '',
    this.setUnit = SetUnit.percent,
    this.sets = const [],
    this.coachNotes = '',
    this.memberNotes = '',
    this.movementId,
    this.workoutName = '',
  });

  factory DailyWorkoutSection.fromJson(Map<String, dynamic> json) =>
      DailyWorkoutSection(
        id: (json['id'] as num?)?.toInt(),
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
        movementId: (json['movement_id'] as num?)?.toInt(),
        workoutName: json['workout_name'] as String? ?? '',
      );

  /// Server id; null for a block that was not saved yet. Sent back on save
  /// so the block is updated in place and keeps what hangs off it.
  final int? id;

  final String title;

  /// Free text for workout blocks; for exercise blocks the readable version
  /// of the sets, so every reader (athletes, older views) still has text.
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

  /// Set by the server from [exerciseName] on exercise blocks.
  final int? movementId;

  /// Named workout (Fran, Murph, a box test) on workout blocks, so a repeat
  /// can be found again.
  final String workoutName;

  bool get isScored => scoreType != WorkoutSectionScore.none;

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'title': title,
    'description': description,
    'score_type': workoutSectionScoreToWire(scoreType),
    'kind': kind.name,
    'exercise_name': exerciseName,
    'set_unit': setUnit.name,
    'sets': [for (final set in sets) set.toJson()],
    'coach_notes': coachNotes,
    'member_notes': memberNotes,
    'workout_name': workoutName,
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
  });

  final int id;
  final int gymId;
  final DateTime scheduledDate;
  final String title;
  final List<DailyWorkoutSection> sections;
  final DailyWorkoutStatus status;
  final DateTime? publishedAt;
  final bool canEdit;

  bool get isPublished => status == DailyWorkoutStatus.published;
}
