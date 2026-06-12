import 'package:app/core/presentation/app_chrome.dart';
import 'package:flutter/material.dart';

/// A premium card surface used everywhere the UI needs a contained block of
/// content. Tap targets become a single `Material` so ink ripples land on top
/// of the rounded corners cleanly.
///
/// Variants:
///   - [AppCard]          — standard card (graphite + hairline)
///   - [AppCard.elevated] — hero card with a subtle gradient + shadow
///   - [AppCard.inset]    — borderless inset surface, for rows inside cards
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(appSpaceLg),
    this.onTap,
    this.radius = appRadiusLg,
  })  : _variant = _AppCardVariant.standard;

  const AppCard.elevated({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(appSpaceLg),
    this.onTap,
    this.radius = appRadiusXl,
  })  : _variant = _AppCardVariant.elevated;

  const AppCard.inset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(appSpaceMd),
    this.onTap,
    this.radius = appRadiusMd,
  })  : _variant = _AppCardVariant.inset;

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final _AppCardVariant _variant;

  @override
  Widget build(BuildContext context) {
    final decoration = switch (_variant) {
      _AppCardVariant.standard => appPanelDecoration(radius: radius),
      _AppCardVariant.elevated => appHeroDecoration(radius: radius),
      _AppCardVariant.inset => appInsetDecoration(radius: radius),
    };
    final content = Padding(padding: padding, child: child);

    if (onTap == null) {
      return Container(decoration: decoration, child: content);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: appPrimarySoft,
        highlightColor: Colors.transparent,
        child: Ink(decoration: decoration, child: content),
      ),
    );
  }
}

enum _AppCardVariant { standard, elevated, inset }
