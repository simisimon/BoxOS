import 'dart:math' as math;

import 'package:app/core/presentation/app_chrome.dart';
import 'package:flutter/material.dart';

/// Opens [builder]'s panel on the right over the current page, which stays
/// visible behind a dimmed barrier (docs/admin-ui-reference.md §0). Resolves
/// to what the panel pops, like [showDialog].
Future<T?> showAppSidePanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 560,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: appScrim,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: math.min(width, MediaQuery.sizeOf(context).width),
        height: double.infinity,
        child: Material(
          color: appSurfaceElevated,
          child: SafeArea(left: false, child: builder(context)),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// One tab of an [AppSidePanel]: label, optional count badge, content.
class AppPanelTab {
  const AppPanelTab(this.label, {required this.child, this.count});

  final String label;
  final int? count;
  final Widget child;
}

/// Right-side panel frame for detail and create flows: header with title,
/// optional status pill, `⋯` menu and `×`; scrolling body or tabs; action bar.
/// Takes the same arguments as AppFormDialog so flows move over unchanged.
class AppSidePanel extends StatelessWidget {
  const AppSidePanel({
    super.key,
    required this.title,
    this.subtitle,
    this.status,
    this.menu = const [],
    this.child,
    this.tabs,
    this.actions = const [],
    this.leading,
    this.bodyPadding = const EdgeInsets.all(20),
  }) : assert((child == null) != (tabs == null), 'Pass child or tabs');

  final String title;
  final String? subtitle;

  /// Shown after the title, e.g. an `AppPill`.
  final Widget? status;

  /// Entries of the `⋯` menu; the panel closes before an entry runs.
  final List<(String label, VoidCallback onSelected)> menu;
  final Widget? child;
  final List<AppPanelTab>? tabs;
  final List<Widget> actions;

  /// Left of the action bar, e.g. a secondary "Archive" button.
  final Widget? leading;
  final EdgeInsets bodyPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The app theme makes Filled/Outlined buttons full-width, which is an
    // infinite width inside the action bar.
    const compact = WidgetStatePropertyAll(Size(0, 44));
    final actionTheme = theme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: (theme.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          minimumSize: compact,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
            .copyWith(minimumSize: compact),
      ),
    );

    Widget scroll(Widget content) =>
        SingleChildScrollView(padding: bodyPadding, child: content);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: appSpaceSm,
                  runSpacing: appSpaceXs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    ?status,
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: appSubtleText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (menu.isNotEmpty)
            PopupMenuButton<int>(
              tooltip: 'More',
              color: appSurfaceElevated,
              icon: const Icon(Icons.more_horiz_rounded, color: appMutedText),
              onSelected: (index) {
                Navigator.of(context).pop();
                menu[index].$2();
              },
              itemBuilder: (_) => [
                for (var i = 0; i < menu.length; i++)
                  PopupMenuItem(value: i, child: Text(menu[i].$1)),
              ],
            ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, color: appMutedText),
          ),
        ],
      ),
    );

    final body = tabs == null
        ? scroll(child!)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tabs: [
                  for (final tab in tabs!)
                    Tab(
                      text: tab.count == null
                          ? tab.label
                          : '${tab.label} ${tab.count}',
                    ),
                ],
              ),
              const Divider(height: 1, color: appBorder),
              Expanded(
                child: TabBarView(
                  // Keep each tab alive so unsaved input survives a tab switch.
                  children: [
                    for (final tab in tabs!)
                      _KeepAlive(child: scroll(tab.child)),
                  ],
                ),
              ),
            ],
          );

    final panel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (tabs == null) const Divider(height: 1, color: appBorder),
        Expanded(child: body),
        if (actions.isNotEmpty || leading != null) ...[
          const Divider(height: 1, color: appBorder),
          Theme(
            data: actionTheme,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 14),
              child: Row(
                children: [
                  ?leading,
                  // Stacks the actions instead of overflowing on phones.
                  Expanded(
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 8,
                      overflowSpacing: 8,
                      overflowAlignment: OverflowBarAlignment.end,
                      children: actions,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: appBorderStrong)),
      ),
      child: tabs == null
          ? panel
          : DefaultTabController(length: tabs!.length, child: panel),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
