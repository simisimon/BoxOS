import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:flutter/material.dart';

/// One accent per class type so the calendar, day panel and week plan read
/// the same at a glance. WOD keeps the brand cyan; Open Gym stays neutral.
/// Looked up by name so models parsed before the custom types loaded still
/// get their colour.
Color classTypeColor(ClassType type) =>
    classTypeColorFor(ClassType.fromWire(type.wireValue).colorKey);

/// Colour keys an owner can pick for a custom type, in picker order.
const classTypeColorKeys = [
  'primary',
  'info',
  'success',
  'warning',
  'danger',
  'muted',
];

/// Name read out for a colour key, e.g. in the colour picker.
String classTypeColorName(String key) => switch (key) {
  'primary' => 'Cyan',
  'success' => 'Green',
  'warning' => 'Amber',
  'danger' => 'Red',
  'muted' => 'Grey',
  _ => 'Blue',
};

Color classTypeColorFor(String key) => switch (key) {
  'primary' => appPrimary,
  'success' => appSuccess,
  'warning' => appWarning,
  'danger' => appDanger,
  'muted' => appMutedText,
  _ => appInfo,
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
