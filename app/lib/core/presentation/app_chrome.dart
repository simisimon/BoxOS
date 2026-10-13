import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
// One restrained accent color. Neon cyan reads premium on near-black, works as
// a button background with white text, carries the restrained cyberpunk accent
// of the BoxOS wireframes, and stays out of the way when used sparingly for
// focus, links, and highlights.
const appPrimary = Color(0xFF00E5FF);
const appPrimarySoft = Color(0x2400E5FF); // ~14% — chips, hover backgrounds
const appPrimaryHairline = Color(0x6600E5FF); // ~40% — borders, dividers

const appDanger = Color(0xFFFF5C6E);
const appDangerSoft = Color(0x33FF5C6E);
const appSuccess = Color(0xFF3DDC97);
const appWarning = Color(0xFFFFB454);
const appInfo = Color(0xFF5BC0FF);

// --- Radii ------------------------------------------------------------------
// Sharp, angular scale to match the BoxOS wireframes — near-square corners with
// just enough softening to avoid a hard pixel edge. The previous pillowy range
// (10–22) read consumer-app; these read like an operations console.
const double appRadiusSm = 3; // inputs, chips, buttons
const double appRadiusMd = 4; // small cards, popovers
const double appRadiusLg = 6; // standard cards
const double appRadiusXl = 8; // hero cards, sheets
const double appRadiusPill = 999;

// --- Chamfer ----------------------------------------------------------------
// The BoxOS CTA silhouette from the wireframes: a single angled cut on the
// bottom-right corner (a `clip-path` polygon), the other three corners square.
// Expressed as a real OutlinedBorder so buttons keep ink, focus and border
// behavior. Applied to filled buttons; outlined/ghost stay square.
const double appButtonCut = 12;
BoxCutBorder appButtonShape({double cut = appButtonCut}) => BoxCutBorder(cut: cut);

/// Rectangle with the bottom-right corner sliced off at 45°. [cut] is the
/// length (in px) trimmed along each edge at that corner.
class BoxCutBorder extends OutlinedBorder {
  const BoxCutBorder({this.cut = appButtonCut, super.side = BorderSide.none});

  final double cut;

  @override
  BoxCutBorder copyWith({BorderSide? side, double? cut}) =>
      BoxCutBorder(cut: cut ?? this.cut, side: side ?? this.side);

  Path _path(Rect rect) {
    final c = cut.clamp(0, rect.shortestSide);
    return Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.bottom - c)
      ..lineTo(rect.right - c, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      BoxCutBorder(cut: cut * t, side: side.scale(t));
}

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
// Typography helpers
// ============================================================================

/// JetBrains Mono eyebrow / micro-label — the BoxOS "operational" voice used
/// for section eyebrows, KPI captions, status chips and timestamps. Uppercase
/// the text at the call site; this only carries the face, tracking and weight.
TextStyle appMono({
  double fontSize = 11,
  FontWeight fontWeight = FontWeight.w700,
  double letterSpacing = 1.4,
  Color color = appSubtleText,
  double? height,
}) => GoogleFonts.jetBrainsMono(
  fontSize: fontSize,
  fontWeight: fontWeight,
  letterSpacing: letterSpacing,
  color: color,
  height: height,
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

/// Page background with the wireframe's faint cyan blueprint grid painted over
/// the base gradient. Drop-in replacement for `DecoratedBox(decoration:
/// appPageDecoration())` — the grid sits behind content, above the gradient.
class AppGridBackground extends StatelessWidget {
  const AppGridBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: appPageDecoration(),
      child: CustomPaint(
        painter: _GridPainter(),
        isComplex: false,
        willChange: false,
        child: child,
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  static const double _step = 48;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = appPrimary.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += _step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += _step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

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
                  style: appMono(fontSize: 10, letterSpacing: 1.4),
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
