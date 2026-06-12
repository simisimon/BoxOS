import 'package:flutter/material.dart';

// ============================================================================
// BoxOS design tokens — dark-first, premium, restrained.
//
// Names are preserved from the previous (light) palette so every screen picks
// up the new look without an import sweep. Treat these as the single source of
// truth: never inline hex colors or magic radii in feature code.
// ============================================================================

// --- Surfaces ---------------------------------------------------------------
// A narrow near-black ramp gives cards a real sense of elevation without
// resorting to drop shadows the eye perceives as gray bands on dark UIs.
const appPageBackground = Color(0xFF07080B);
const appPageBackgroundSoft = Color(0xFF0B0D12);
const appPageBackgroundEnd = Color(0xFF07080B);
const appSurface = Color(0xFF101218);
const appSurfaceAlt = Color(0xFF161922);
const appSurfaceElevated = Color(0xFF1B1F2A);

// --- Borders ----------------------------------------------------------------
const appBorder = Color(0xFF1F2330);
const appBorderStrong = Color(0xFF2A2F3D);

// --- Text -------------------------------------------------------------------
const appText = Color(0xFFF4F5F7);
const appMutedText = Color(0xFFAEB4BD);
const appSubtleText = Color(0xFF767C86);
const appInverseText = Color(0xFF07080B); // for use on light accents

// --- Brand & semantic accents ----------------------------------------------
// One restrained accent color. Electric indigo reads premium on near-black,
// works as a button background with white text, and stays out of the way when
// used sparingly for focus, links, and highlights.
const appPrimary = Color(0xFF5B6FFF);
const appPrimarySoft = Color(0x335B6FFF); // ~20% — chips, hover backgrounds
const appPrimaryHairline = Color(0x665B6FFF); // ~40% — borders, dividers

const appDanger = Color(0xFFFF5C6E);
const appDangerSoft = Color(0x33FF5C6E);
const appSuccess = Color(0xFF3DDC97);
const appWarning = Color(0xFFFFB454);
const appInfo = Color(0xFF5BC0FF);

// --- Radii ------------------------------------------------------------------
// Tightened scale; the previous range (16–28) read pillowy. These match Linear
// and Stripe dashboard surfaces — confident, precise, never childish.
const double appRadiusSm = 10; // inputs, chips, small pills
const double appRadiusMd = 14; // small cards, popovers
const double appRadiusLg = 18; // standard cards
const double appRadiusXl = 22; // hero cards, sheets
const double appRadiusPill = 999;

// --- Spacing ---------------------------------------------------------------
// Centralized so every screen breathes the same way. Use these for vertical
// rhythm between sections, list rows, and inside cards.
const double appSpaceXs = 4;
const double appSpaceSm = 8;
const double appSpaceMd = 12;
const double appSpaceLg = 16;
const double appSpaceXl = 20;
const double appSpace2xl = 24;
const double appSpace3xl = 32;

// --- Shadows ---------------------------------------------------------------
// On dark, "shadow" is really an even-darker pool underneath cards. Keep the
// alpha generous; subtle on-light shadows disappear here.
const _shadowPanel = BoxShadow(
  color: Color(0x80000000),
  blurRadius: 24,
  offset: Offset(0, 14),
);
const _shadowHero = BoxShadow(
  color: Color(0x99000000),
  blurRadius: 36,
  offset: Offset(0, 22),
);

// ============================================================================
// Reusable decorations
// ============================================================================

BoxDecoration appPageDecoration() => const BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [appPageBackground, appPageBackgroundSoft, appPageBackgroundEnd],
  ),
);

BoxDecoration appPanelDecoration({double radius = appRadiusLg}) =>
    BoxDecoration(
      color: appSurface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: appBorder),
      boxShadow: const [_shadowPanel],
    );

BoxDecoration appHeroDecoration({double radius = appRadiusXl}) => BoxDecoration(
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: appBorderStrong),
  gradient: const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [appSurfaceElevated, appSurface],
  ),
  boxShadow: const [_shadowHero],
);

/// Subtle card decoration for inline content (rows nested inside larger
/// cards). No shadow — just a quiet surface with a hairline border.
BoxDecoration appInsetDecoration({double radius = appRadiusMd}) =>
    BoxDecoration(
      color: appSurfaceAlt,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: appBorder),
    );

// ============================================================================
// Legacy shared widgets
//
// Kept for backwards compatibility with feature screens that already consume
// them. New code should prefer the components in
// `core/presentation/components/`.
// ============================================================================

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
      color: appSurfaceAlt,
      borderRadius: BorderRadius.circular(appRadiusLg),
      border: Border.all(color: appBorder),
    );
    final child = Padding(
      padding: const EdgeInsets.all(appSpaceLg),
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
                    color: appSubtleText,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (icon != null) Icon(icon, size: 16, color: accentColor),
            ],
          ),
          const SizedBox(height: appSpaceSm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: appText,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
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

/// Rounded square icon badge with an accent-tinted surface, used across
/// feature cards, list tiles, and section headers.
class AppAccentBadge extends StatelessWidget {
  const AppAccentBadge({
    super.key,
    required this.icon,
    this.color = appPrimary,
    this.size = 44,
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
        color: Color.alphaBlend(color.withValues(alpha: 0.18), appSurfaceAlt),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}
