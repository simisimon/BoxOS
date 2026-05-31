enum WorkoutType {
  fitness,
  crossfit;

  String get apiValue => switch (this) {
    WorkoutType.fitness => 'fitness',
    WorkoutType.crossfit => 'crossfit',
  };

  String get label => switch (this) {
    WorkoutType.fitness => 'Fitness',
    WorkoutType.crossfit => 'CrossFit',
  };

  static WorkoutType fromApi(String value) => switch (value) {
    'crossfit' => WorkoutType.crossfit,
    _ => WorkoutType.fitness,
  };
}

/// A user-owned workout template (Fitness or CrossFit). The [structure] map is
/// type-specific and intentionally free-form on the backend:
///  - CrossFit: { format, time_cap_minutes?, rounds?, score_type, movements: [{name, reps, weight}] }
///  - Fitness:  { exercises: [{name, sets, reps, weight}] }
class PersonalWorkout {
  const PersonalWorkout({
    required this.id,
    required this.type,
    required this.title,
    required this.structure,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final WorkoutType type;
  final String title;
  final Map<String, dynamic> structure;
  final DateTime createdAt;
  final DateTime updatedAt;

  String? get format => structure['format'] as String?;

  List<Map<String, dynamic>> get movements => _itemList('movements');

  List<Map<String, dynamic>> get exercises => _itemList('exercises');

  List<Map<String, dynamic>> _itemList(String key) {
    final raw = structure[key];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  factory PersonalWorkout.fromJson(Map<String, dynamic> json) {
    return PersonalWorkout(
      id: json['id'] as int? ?? 0,
      type: WorkoutType.fromApi(json['type'] as String? ?? 'fitness'),
      title: json['title'] as String? ?? '',
      structure:
          (json['structure'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
