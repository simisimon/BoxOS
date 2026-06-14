import 'package:app/core/presentation/responsive/breakpoints.dart';
import 'package:flutter/material.dart';

/// Wraps page content in a centered column whose maximum width adapts to the
/// current window size class (see [AppBreakpoint] / [BreakpointContext]).
///
/// On phones it fills the screen; on larger windows it caps the width so the
/// content stays readable instead of stretching across the full viewport.
class MobileContent extends StatelessWidget {
  const MobileContent({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class MobileScrollableContent extends StatelessWidget {
  const MobileScrollableContent({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return MobileContent(
      alignment: alignment,
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(padding: padding, child: child),
    );
  }
}
