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

  String get divisionLabel => division == ResultDivision.rx ? 'Rx' : 'Scaled';
}
