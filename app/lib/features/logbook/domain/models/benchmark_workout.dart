class BenchmarkWorkout {
  const BenchmarkWorkout({
    required this.id,
    required this.name,
    required this.category,
    required this.structure,
  });

  final String id;
  final String name;

  /// 'girl' or 'hero'.
  final String category;
  final Map<String, dynamic> structure;

  List<Map<String, dynamic>> get movements {
    final raw = structure['movements'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
  }

  factory BenchmarkWorkout.fromJson(Map<String, dynamic> json) {
    return BenchmarkWorkout(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      structure:
          (json['structure'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
    );
  }
}
