import 'package:flutter/material.dart';

const double mobileContentMaxWidth = 480;

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
        constraints: const BoxConstraints(maxWidth: mobileContentMaxWidth),
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
