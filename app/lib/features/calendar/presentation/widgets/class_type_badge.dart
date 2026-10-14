import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:flutter/material.dart';

/// One accent per class type so the calendar, day panel and week plan read
/// the same at a glance. WOD keeps the brand cyan; Open Gym stays neutral.
Color classTypeColor(ClassType type) => switch (type) {
  ClassType.wod => appPrimary,
  ClassType.openGym => appMutedText,
  ClassType.skill => appWarning,
  ClassType.pt => appSuccess,
};

/// Compact uppercase type tag, e.g. `WOD` or `OPEN GYM`.
class ClassTypeBadge extends StatelessWidget {
  const ClassTypeBadge({super.key, required this.type, this.dense = false});

  final ClassType type;

  /// Smaller variant for tight spots like week-plan chips.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = classTypeColor(type);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 5 : 8,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        type.label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: appMono(
          fontSize: dense ? 8.5 : 10,
          letterSpacing: dense ? 0.4 : 1.0,
          color: color,
        ),
      ),
    );
  }
}
