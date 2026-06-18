import 'package:flutter/material.dart';

enum TimerMode { stopwatch, amrap, emom }

enum TrackableSource {
  personal,
  benchmark,
  daily;

  String get apiValue => switch (this) {
        TrackableSource.personal => 'personal',
        TrackableSource.benchmark => 'benchmark',
        TrackableSource.daily => 'daily',
      };
}

enum TrackingScoreType {
  time,
  roundsReps,
  load;

  String get apiValue => switch (this) {
        TrackingScoreType.time => 'time',
        TrackingScoreType.roundsReps => 'rounds_reps',
        TrackingScoreType.load => 'load',
      };

  String get label => switch (this) {
        TrackingScoreType.time => 'Time',
        TrackingScoreType.roundsReps => 'Rounds + Reps',
        TrackingScoreType.load => 'Weight (kg)',
      };

  static TrackingScoreType fromApi(String value) => switch (value) {
        'rounds_reps' => TrackingScoreType.roundsReps,
        'load' => TrackingScoreType.load,
        _ => TrackingScoreType.time,
      };
}

class TrackableMovement {
  const TrackableMovement({required this.name, this.detail});

  final String name;
  final String? detail;
}

/// Unified representation of any workout the user can pick from the Tracking
/// picker, so the timer screen doesn't care which repository it came from.
class TrackableWorkout {
  const TrackableWorkout({
    required this.source,
    required this.sourceKey,
    required this.title,
    required this.subtitle,
    required this.movements,
    required this.suggestedMode,
    required this.accent,
    this.suggestedMinutes,
    this.suggestedIntervalSeconds,
  });

  final TrackableSource source;
  /// Stable identifier within [source] (e.g. the numeric id as a string for
  /// personal/daily workouts, or the slug for a benchmark).
  final String sourceKey;
  final String title;
  final String subtitle;
  final List<TrackableMovement> movements;
  final TimerMode suggestedMode;
  final Color accent;
  final int? suggestedMinutes;
  final int? suggestedIntervalSeconds;

  /// The score type that fits the suggested timer mode by default.
  TrackingScoreType get suggestedScoreType {
    switch (suggestedMode) {
      case TimerMode.stopwatch:
        return TrackingScoreType.time;
      case TimerMode.amrap:
        return TrackingScoreType.roundsReps;
      case TimerMode.emom:
        return TrackingScoreType.time;
    }
  }
}

/// A saved tracking attempt for a specific workout.
class TrackingSession {
  const TrackingSession({
    required this.id,
    required this.sourceKind,
    required this.sourceKey,
    required this.workoutTitle,
    required this.scoreType,
    required this.scoreValue,
    required this.scoreLabel,
    required this.notesText,
    required this.createdAt,
  });

  final int id;
  final String sourceKind;
  final String sourceKey;
  final String workoutTitle;
  final TrackingScoreType scoreType;
  final double scoreValue;
  final String scoreLabel;
  final String notesText;
  final DateTime createdAt;

  factory TrackingSession.fromJson(Map<String, dynamic> json) {
    return TrackingSession(
      id: json['id'] as int? ?? 0,
      sourceKind: json['source_kind'] as String? ?? '',
      sourceKey: json['source_key'] as String? ?? '',
      workoutTitle: json['workout_title'] as String? ?? '',
      scoreType: TrackingScoreType.fromApi(
        json['score_type'] as String? ?? 'time',
      ),
      scoreValue: (json['score_value'] as num?)?.toDouble() ?? 0,
      scoreLabel: json['score_label'] as String? ?? '',
      notesText: json['notes_text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}

TimerMode timerModeFromFormat(String? format) {
  switch (format) {
    case 'amrap':
      return TimerMode.amrap;
    case 'emom':
      return TimerMode.emom;
    case 'for_time':
    case 'rounds':
    default:
      return TimerMode.stopwatch;
  }
}

String timerModeLabel(TimerMode mode) {
  switch (mode) {
    case TimerMode.stopwatch:
      return 'Stopwatch';
    case TimerMode.amrap:
      return 'AMRAP';
    case TimerMode.emom:
      return 'EMOM';
  }
}
