class GymSummary {
  const GymSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.logoUrl,
    required this.timezone,
  });

  final int id;
  final String name;
  final String slug;
  final String logoUrl;
  final String timezone;
}
