import 'package:flutter/widgets.dart';

/// Lays its [children] out in a responsive number of columns, derived from the
/// *actual* available width (via [LayoutBuilder], not the whole window) so it
/// behaves correctly inside padded or split layouts.
///
/// Columns are filled round-robin (masonry), which keeps the global reading
/// order left-to-right and balances columns of differing heights — ideal for
/// dashboards of variable-height panels or uniform card lists. At a single
/// column it degrades to a plain vertical stack, so the same call site works
/// on phones and desktops.
class ResponsiveMasonry extends StatelessWidget {
  const ResponsiveMasonry({
    super.key,
    required this.children,
    this.minColumnWidth = 320,
    this.maxColumns = 3,
    this.spacing = 16,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;

  /// Minimum width a column may shrink to before dropping a column.
  final double minColumnWidth;

  /// Hard cap on the number of columns regardless of how wide the area is.
  final int maxColumns;

  /// Gap between columns and between stacked items within a column.
  final double spacing;

  final CrossAxisAlignment crossAxisAlignment;

  int _columnCountFor(double width) {
    if (width.isInfinite || width <= 0) return 1;
    final raw = ((width + spacing) / (minColumnWidth + spacing)).floor();
    return raw.clamp(1, maxColumns);
  }

  List<Widget> _stack(List<Widget> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.add(SizedBox(height: spacing));
      out.add(items[i]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnCountFor(constraints.maxWidth);
        if (columns <= 1) {
          return Column(
            crossAxisAlignment: crossAxisAlignment,
            children: _stack(children),
          );
        }

        final buckets = List.generate(columns, (_) => <Widget>[]);
        for (var i = 0; i < children.length; i++) {
          buckets[i % columns].add(children[i]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) SizedBox(width: spacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: crossAxisAlignment,
                  children: _stack(buckets[c]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
