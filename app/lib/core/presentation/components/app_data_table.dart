import 'package:app/core/presentation/app_chrome.dart';
import 'package:flutter/material.dart';

/// One column of an [AppDataTable].
class AppTableColumn {
  const AppTableColumn(
    this.label, {
    this.flex = 1,
    this.sortable = false,
    this.hideWhenNarrow = false,
  });

  final String label;
  final int flex;
  final bool sortable;

  /// Dropped below 600px so phones keep the essential columns.
  final bool hideWhenNarrow;
}

/// Admin-layout table (docs/admin-ui-reference.md §0): small muted headers,
/// sortable columns with an arrow, row click, "Showing x of y" footer. Fills
/// the height it is given and scrolls its rows.
///
/// shortcut: no pagination, rows are virtualised instead; add pages once a
/// list comes from a paged endpoint.
class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.cells,
    this.total,
    this.onRowTap,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.emptyText = 'Nothing to show.',
    this.shrinkWrap = false,
  });

  final List<AppTableColumn> columns;
  final List<T> rows;

  /// One widget per column, in column order.
  final List<Widget> Function(T row) cells;

  /// Total before filtering, for the footer; defaults to [rows].length.
  final int? total;
  final ValueChanged<T>? onRowTap;
  final int? sortColumn;
  final bool sortAscending;
  final ValueChanged<int>? onSort;
  final String emptyText;

  /// Size to the rows instead of filling the parent (for tables inside a
  /// scrolling page).
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final visible = [
          for (var i = 0; i < columns.length; i++)
            if (!(narrow && columns[i].hideWhenNarrow)) i,
        ];
        Widget line(List<Widget> children) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: appSpaceLg,
            vertical: appSpaceMd,
          ),
          child: Row(
            children: [
              for (var j = 0; j < visible.length; j++)
                Expanded(
                  flex: columns[visible[j]].flex,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: j == visible.length - 1 ? 0 : appSpaceMd,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: children[j],
                    ),
                  ),
                ),
            ],
          ),
        );

        final header = line([
          for (final i in visible)
            _HeaderCell(
              column: columns[i],
              sortedAscending: sortColumn == i ? sortAscending : null,
              onTap: columns[i].sortable && onSort != null
                  ? () => onSort!(i)
                  : null,
            ),
        ]);

        final body = rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(appSpace2xl),
                child: Center(
                  child: Text(
                    emptyText,
                    style: const TextStyle(color: appSubtleText),
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: shrinkWrap,
                physics: shrinkWrap
                    ? const NeverScrollableScrollPhysics()
                    : null,
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: appBorder),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final all = cells(row);
                  return InkWell(
                    onTap: onRowTap == null ? null : () => onRowTap!(row),
                    hoverColor: appSurfaceAlt,
                    child: line([for (final i in visible) all[i]]),
                  );
                },
              );

        return Container(
          decoration: BoxDecoration(
            color: appSurface,
            borderRadius: BorderRadius.circular(appRadiusLg),
            border: Border.all(color: appBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const Divider(height: 1, color: appBorder),
              if (shrinkWrap) body else Expanded(child: body),
              const Divider(height: 1, color: appBorder),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: appSpaceLg,
                  vertical: appSpaceSm + 2,
                ),
                child: Text(
                  'Showing ${rows.length} of ${total ?? rows.length}',
                  style: const TextStyle(color: appSubtleText, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.sortedAscending,
    required this.onTap,
  });

  final AppTableColumn column;

  /// null when the table is not sorted by this column.
  final bool? sortedAscending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            column.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: sortedAscending == null ? appSubtleText : appMutedText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (column.sortable) ...[
          const SizedBox(width: appSpaceXs),
          Icon(
            sortedAscending == false
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            size: 13,
            color: sortedAscending == null ? appBorderStrong : appPrimary,
          ),
        ],
      ],
    );
    if (onTap == null) return label;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(appRadiusSm),
      child: label,
    );
  }
}
