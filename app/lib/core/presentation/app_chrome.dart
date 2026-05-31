import 'package:flutter/material.dart';

const appPageBackground = Color(0xFFF5F9FF);
const appPageBackgroundSoft = Color(0xFFEAF2FF);
const appPageBackgroundEnd = Color(0xFFF9FBFF);
const appSurface = Colors.white;
const appSurfaceAlt = Color(0xFFF8FBFF);
const appBorder = Color(0xFFD8E4F2);
const appText = Color(0xFF0F172A);
const appMutedText = Color(0xFF475569);
const appSubtleText = Color(0xFF64748B);
const appPrimary = Color(0xFF2563EB);
const appDanger = Color(0xFFD64545);

// Corner-radius scale. Use these instead of raw BorderRadius.circular(...)
// literals so card, field, badge, and pill rounding stays in lockstep.
const double appRadiusSm = 16;
const double appRadiusMd = 18;
const double appRadiusLg = 24;
const double appRadiusXl = 28;
const double appRadiusPill = 999;

BoxDecoration appPageDecoration() => const BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [appPageBackground, appPageBackgroundSoft, appPageBackgroundEnd],
  ),
);

BoxDecoration appPanelDecoration({double radius = appRadiusXl}) =>
    BoxDecoration(
      color: appSurface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: appBorder),
      boxShadow: const [
        BoxShadow(
          color: Color(0x120F172A),
          blurRadius: 24,
          offset: Offset(0, 12),
        ),
      ],
    );

BoxDecoration appHeroDecoration({double radius = appRadiusXl}) => BoxDecoration(
  color: appSurface,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: appBorder),
  boxShadow: const [
    BoxShadow(color: Color(0x120F172A), blurRadius: 28, offset: Offset(0, 14)),
  ],
);

/// Compact stat tile (label + value) used in snapshot/dashboard grids. Pass an
/// optional [icon] for a trailing accent glyph and [onTap] to make the tile
/// double as a quick-access shortcut. Shared by the Logbook and Home screens.
class AppStatTile extends StatelessWidget {
  const AppStatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accentColor = appPrimary,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = BoxDecoration(
      color: accentColor.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(appRadiusLg),
      border: Border.all(color: accentColor.withValues(alpha: 0.22)),
    );
    final child = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (icon != null) Icon(icon, size: 18, color: accentColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: appText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Container(decoration: decoration, child: child);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusLg),
        onTap: onTap,
        child: Ink(decoration: decoration, child: child),
      ),
    );
  }
}

/// Rounded square icon badge with an accent-tinted gradient, used across
/// feature cards, list tiles, and section headers. Consolidates what used to
/// be a dozen identical private `_AccentBadge` copies.
class AppAccentBadge extends StatelessWidget {
  const AppAccentBadge({
    super.key,
    required this.icon,
    this.color = appPrimary,
    this.size = 50,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(appRadiusMd),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Icon(icon, color: color),
    );
  }
}
