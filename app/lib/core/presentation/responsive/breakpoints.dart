import 'package:flutter/widgets.dart';

/// Material 3 window size classes. These drive every responsive/adaptive
/// decision in the app, so layout breakpoints live in exactly one place
/// instead of being scattered as magic numbers across screens.
///
/// Thresholds follow the canonical Material 3 breakpoints:
/// https://m3.material.io/foundations/layout/applying-layout/window-size-classes
enum AppBreakpoint {
  /// Phones in portrait (< 600).
  compact,

  /// Small tablets / large foldables / phones in landscape (600–839).
  medium,

  /// Tablets in landscape / small desktop windows (840–1199).
  expanded,

  /// Desktop and larger (>= 1200).
  large;

  bool isAtLeast(AppBreakpoint other) => index >= other.index;
}

/// Maps a raw width (logical pixels) to its [AppBreakpoint].
AppBreakpoint breakpointForWidth(double width) {
  if (width < 600) return AppBreakpoint.compact;
  if (width < 840) return AppBreakpoint.medium;
  if (width < 1200) return AppBreakpoint.expanded;
  return AppBreakpoint.large;
}

/// Readable maximum width for the primary content column at each size class.
///
/// Compact fills the whole screen (phones); wider classes cap the column so
/// text lines and forms stay readable instead of stretching edge-to-edge on a
/// large monitor.
double contentMaxWidthFor(AppBreakpoint breakpoint) {
  switch (breakpoint) {
    case AppBreakpoint.compact:
      return double.infinity;
    case AppBreakpoint.medium:
      return 720;
    case AppBreakpoint.expanded:
      return 840;
    case AppBreakpoint.large:
      return 960;
  }
}

/// Wider content cap for dashboard / admin surfaces that benefit from a
/// multi-column layout. Roomier than [contentMaxWidthFor] but still bounded so
/// the content does not stretch edge-to-edge on very large monitors.
double dashboardMaxWidthFor(AppBreakpoint breakpoint) {
  switch (breakpoint) {
    case AppBreakpoint.compact:
      return double.infinity;
    case AppBreakpoint.medium:
      return 720;
    case AppBreakpoint.expanded:
      return 1120;
    case AppBreakpoint.large:
      return 1360;
  }
}

extension BreakpointContext on BuildContext {
  /// The current window size class, derived from the window width.
  AppBreakpoint get appBreakpoint =>
      breakpointForWidth(MediaQuery.sizeOf(this).width);

  /// Readable max width for the primary content column at the current size.
  double get contentMaxWidth => contentMaxWidthFor(appBreakpoint);

  /// Wider max width for dashboard / admin surfaces (see [dashboardMaxWidthFor]).
  double get dashboardMaxWidth => dashboardMaxWidthFor(appBreakpoint);

  /// Whether the layout should use a side [NavigationRail] instead of a bottom
  /// navigation bar. True from the `expanded` size class upwards.
  bool get usesNavigationRail =>
      appBreakpoint.isAtLeast(AppBreakpoint.expanded);
}
