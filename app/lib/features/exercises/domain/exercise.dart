class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.equipment,
    required this.level,
    required this.primaryMuscles,
    required this.secondaryMuscles,
  });

  final String id;
  final String name;
  final String category;
  final String equipment;
  final String level;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;

  String get subtitle => [
    if (primaryMuscles.isNotEmpty) primaryMuscles.join(', '),
    if (equipment.isNotEmpty && equipment != 'body only') equipment,
  ].join(' · ');

  factory Exercise.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? raw) =>
        (raw is List ? raw : const []).map((item) => item.toString()).toList();
    return Exercise(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      equipment: json['equipment'] as String? ?? '',
      level: json['level'] as String? ?? '',
      primaryMuscles: strings(json['primary_muscles']),
      secondaryMuscles: strings(json['secondary_muscles']),
    );
  }
}
