class DailyWorkout {
  const DailyWorkout({
    required this.id,
    required this.gymId,
    required this.scheduledDate,
    required this.title,
    required this.strengthText,
    required this.metconText,
    required this.notesText,
    required this.canEdit,
  });

  final int id;
  final int gymId;
  final DateTime scheduledDate;
  final String title;
  final String strengthText;
  final String metconText;
  final String notesText;
  final bool canEdit;
}
