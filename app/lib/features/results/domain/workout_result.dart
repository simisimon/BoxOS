/// Rx or Scaled; the leaderboard ranks Rx first.
enum ResultDivision { rx, scaled }

/// One set of an exercise block as lifted: [reps] at [kg].
class ResultSet {
  const ResultSet({required this.reps, this.kg});

  factory ResultSet.fromJson(Map<String, dynamic> json) => ResultSet(
    reps: (json['reps'] as num? ?? 0).toInt(),
    kg: (json['kg'] as num?)?.toDouble(),
  );

  final int reps;
  final double? kg;

  Map<String, dynamic> toJson() => {'reps': reps, 'kg': kg};
}

/// An athlete's result on one scored WOD block.
class WorkoutResult {
  const WorkoutResult({
    required this.id,
    required this.sectionId,
    required this.performedOn,
    required this.scoreLabel,
    required this.scoreValue,
    required this.division,
    this.timeCapped = false,
    this.sets = const [],
    this.notes = '',
    this.sectionTitle = '',
    this.isPr = false,
  });

  factory WorkoutResult.fromJson(Map<String, dynamic> json) => WorkoutResult(
    id: (json['id'] as num).toInt(),
    sectionId: (json['section_id'] as num?)?.toInt(),
    performedOn: DateTime.parse(json['performed_on'] as String),
    scoreLabel: json['score_label'] as String? ?? '',
    scoreValue: (json['score_value'] as num? ?? 0).toDouble(),
    division: json['division'] == 'scaled'
        ? ResultDivision.scaled
        : ResultDivision.rx,
    timeCapped: json['time_capped'] as bool? ?? false,
    sets: [
      for (final raw in json['sets'] as List? ?? const [])
        ResultSet.fromJson(raw as Map<String, dynamic>),
    ],
    notes: json['notes'] as String? ?? '',
    sectionTitle: json['section_title'] as String? ?? '',
    isPr: json['is_pr'] as bool? ?? false,
  );

  final int id;
  final int? sectionId;
  final DateTime performedOn;

  /// "4:12", "7+14", "100 kg", "CAP · 80 reps".
  final String scoreLabel;
  final double scoreValue;
  final ResultDivision division;
  final bool timeCapped;
  final List<ResultSet> sets;
  final String notes;
  final String sectionTitle;

  /// Beats every earlier result of the same movement or named workout in
  /// the same division (server-side, recomputed on every read).
  final bool isPr;

  String get divisionLabel => division == ResultDivision.rx ? 'Rx' : 'Scaled';
}

/// Heaviest kg lifted for a rep count, across an athlete's sets.
class BestSet {
  const BestSet({required this.reps, required this.kg});

  factory BestSet.fromJson(Map<String, dynamic> json) => BestSet(
    reps: (json['reps'] as num).toInt(),
    kg: (json['kg'] as num).toDouble(),
  );

  final int reps;
  final double kg;
}

/// Estimated one-rep max: the best single, else Epley from the best set.
double? estimatedOneRepMax(List<BestSet> best) {
  double? max;
  for (final set in best) {
    final estimate = set.reps == 1 ? set.kg : set.kg * (1 + set.reps / 30);
    if (max == null || estimate > max) max = estimate;
  }
  return max;
}

/// Earlier results for the same movement or named workout ("Last times").
class ResultHistory {
  const ResultHistory({
    required this.results,
    this.bestIds = const {},
    this.bestSets = const [],
  });

  factory ResultHistory.fromJson(Map<String, dynamic> json) => ResultHistory(
    results: [
      for (final raw in json['results'] as List? ?? const [])
        WorkoutResult.fromJson(raw as Map<String, dynamic>),
    ],
    bestIds: {
      for (final value
          in (json['best'] as Map<String, dynamic>? ?? const {}).values)
        (value as num).toInt(),
    },
    bestSets: [
      for (final raw in json['best_sets'] as List? ?? const [])
        BestSet.fromJson(raw as Map<String, dynamic>),
    ],
  );

  final List<WorkoutResult> results;
  final Set<int> bestIds;
  final List<BestSet> bestSets;
}

/// A movement or named workout the athlete has results for.
class ResultFilter {
  const ResultFilter({
    required this.label,
    required this.count,
    this.movementId,
    this.workoutName = '',
  });

  factory ResultFilter.fromJson(Map<String, dynamic> json) => ResultFilter(
    label: json['label'] as String? ?? '',
    count: (json['count'] as num? ?? 0).toInt(),
    movementId: (json['movement_id'] as num?)?.toInt(),
    workoutName: json['workout_name'] as String? ?? '',
  );

  final String label;
  final int count;
  final int? movementId;
  final String workoutName;

  @override
  bool operator ==(Object other) =>
      other is ResultFilter &&
      other.movementId == movementId &&
      other.workoutName == workoutName;

  @override
  int get hashCode => Object.hash(movementId, workoutName);
}

class MyResults {
  const MyResults({
    required this.results,
    required this.filters,
    this.bestSets = const [],
  });

  factory MyResults.fromJson(Map<String, dynamic> json) => MyResults(
    results: [
      for (final raw in json['results'] as List? ?? const [])
        WorkoutResult.fromJson(raw as Map<String, dynamic>),
    ],
    filters: [
      for (final raw in json['filters'] as List? ?? const [])
        ResultFilter.fromJson(raw as Map<String, dynamic>),
    ],
    bestSets: [
      for (final raw in json['best_sets'] as List? ?? const [])
        BestSet.fromJson(raw as Map<String, dynamic>),
    ],
  );

  final List<WorkoutResult> results;
  final List<ResultFilter> filters;
  final List<BestSet> bestSets;
}

/// One row of a block's leaderboard.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.scoreLabel,
    required this.division,
    this.avatarUrl = '',
    this.isPr = false,
    this.isMe = false,
    this.notes = '',
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        rank: (json['rank'] as num).toInt(),
        name: json['name'] as String? ?? '',
        scoreLabel: json['score_label'] as String? ?? '',
        division: json['division'] == 'scaled'
            ? ResultDivision.scaled
            : ResultDivision.rx,
        avatarUrl: json['avatar_url'] as String? ?? '',
        isPr: json['is_pr'] as bool? ?? false,
        isMe: json['is_me'] as bool? ?? false,
        notes: json['notes'] as String? ?? '',
      );

  final int rank;
  final String name;
  final String scoreLabel;
  final ResultDivision division;
  final String avatarUrl;
  final bool isPr;
  final bool isMe;

  /// Only the athlete's own notes, or everyone's for owners and trainers.
  final String notes;
}
