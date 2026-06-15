enum ScheduleSectionScore {
  time,
  roundsReps,
  weight;

  String get apiValue {
    switch (this) {
      case ScheduleSectionScore.time:
        return 'time';
      case ScheduleSectionScore.roundsReps:
        return 'rounds_reps';
      case ScheduleSectionScore.weight:
        return 'weight';
    }
  }

  String get label {
    switch (this) {
      case ScheduleSectionScore.time:
        return 'Time';
      case ScheduleSectionScore.roundsReps:
        return 'Rounds and Reps';
      case ScheduleSectionScore.weight:
        return 'Weight (kg)';
    }
  }

  static ScheduleSectionScore? fromApi(String? value) {
    switch (value) {
      case 'time':
        return ScheduleSectionScore.time;
      case 'rounds_reps':
        return ScheduleSectionScore.roundsReps;
      case 'weight':
        return ScheduleSectionScore.weight;
      default:
        return null;
    }
  }
}

class ScheduleSection {
  const ScheduleSection({
    required this.title,
    this.description = '',
    this.scoreType,
  });

  final String title;
  final String description;
  final ScheduleSectionScore? scoreType;

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        if (scoreType != null) 'score_type': scoreType!.apiValue,
      };
}
