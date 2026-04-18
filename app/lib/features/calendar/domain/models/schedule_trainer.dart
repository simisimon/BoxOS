class ScheduleTrainer {
  const ScheduleTrainer({
    required this.id,
    required this.displayName,
    required this.nickname,
  });

  final int id;
  final String displayName;
  final String nickname;

  String get label => displayName.isEmpty ? nickname : displayName;
}
