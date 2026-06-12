import 'package:app/core/presentation/app_chrome.dart';
import 'package:flutter/material.dart';

/// Status pill used for state badges (e.g. "BOOKED", "WAITLIST", "FULL").
/// Three intents map to the system semantic colors; `neutral` is the default
/// for chrome metadata that doesn't carry meaning.
enum AppPillIntent { neutral, primary, success, warning, danger }

class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.icon,
    this.intent = AppPillIntent.neutral,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final AppPillIntent intent;
  final bool dense;

  Color get _foreground => switch (intent) {
        AppPillIntent.neutral => appMutedText,
        AppPillIntent.primary => appPrimary,
        AppPillIntent.success => appSuccess,
        AppPillIntent.warning => appWarning,
        AppPillIntent.danger => appDanger,
      };

  Color get _background => switch (intent) {
        AppPillIntent.neutral => appSurfaceAlt,
        AppPillIntent.primary => appPrimarySoft,
        AppPillIntent.success => const Color(0x333DDC97),
        AppPillIntent.warning => const Color(0x33FFB454),
        AppPillIntent.danger => appDangerSoft,
      };

  Color get _border => intent == AppPillIntent.neutral
      ? appBorder
      : _foreground.withValues(alpha: 0.35);

  @override
  Widget build(BuildContext context) {
    final padding = dense
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 5);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(appRadiusPill),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 12, color: _foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: _foreground,
              fontWeight: FontWeight.w800,
              fontSize: dense ? 9.5 : 10.5,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
