import 'package:app/core/presentation/app_chrome.dart';
import 'package:flutter/material.dart';

/// A premium label-value metric block in the WHOOP performance language:
/// small uppercase eyebrow, oversized typographic value, optional trailing
/// delta. Designed to scale from a 90px-tall snapshot tile up to a hero
/// metric in a card. Use [AppMetric.delta] as a typed positive/negative trend.
enum AppMetricTone { neutral, positive, negative }

class AppMetricDelta {
  const AppMetricDelta(this.value, {this.tone = AppMetricTone.neutral});

  /// Pre-formatted ("+12%", "−3"). The caller decides format and sign because
  /// numeric vs. percent vs. duration deltas all read differently.
  final String value;
  final AppMetricTone tone;
}

class AppMetric extends StatelessWidget {
  const AppMetric({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.delta,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.valueSize = 28,
  });

  final String label;
  final String value;
  final String? unit;
  final AppMetricDelta? delta;
  final CrossAxisAlignment crossAxisAlignment;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: appSubtleText,
            fontWeight: FontWeight.w700,
            fontSize: 10.5,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        RichText(
          textAlign: crossAxisAlignment == CrossAxisAlignment.center
              ? TextAlign.center
              : TextAlign.start,
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  color: appText,
                  fontSize: valueSize,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    color: appSubtleText,
                    fontSize: valueSize * 0.55,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        if (delta != null) ...[
          const SizedBox(height: 6),
          _MetricDelta(delta: delta!),
        ],
      ],
    );
  }
}

class _MetricDelta extends StatelessWidget {
  const _MetricDelta({required this.delta});

  final AppMetricDelta delta;

  @override
  Widget build(BuildContext context) {
    final color = switch (delta.tone) {
      AppMetricTone.positive => appSuccess,
      AppMetricTone.negative => appDanger,
      AppMetricTone.neutral => appMutedText,
    };
    final icon = switch (delta.tone) {
      AppMetricTone.positive => Icons.arrow_upward_rounded,
      AppMetricTone.negative => Icons.arrow_downward_rounded,
      AppMetricTone.neutral => Icons.remove_rounded,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 4),
        Text(
          delta.value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
