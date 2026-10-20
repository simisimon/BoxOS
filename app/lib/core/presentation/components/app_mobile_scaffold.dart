import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/responsive/breakpoints.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The scaffold every out-of-shell screen should use.
///
/// Why this exists: GoRouter destinations that live *outside* the
/// `StatefulShellRoute` (settings, analytics, join-requests, schedule
/// management, etc.) should share the same header/body width behaviour as the
/// main shell, so a deep-link from the home screen feels like the same product
/// as the tabs.
///
/// The width adapts to the window size class via [BreakpointContext]: it fills
/// the screen on phones and caps for readability on larger windows.
class AppMobileScaffold extends StatelessWidget {
  const AppMobileScaffold({
    super.key,
    this.title,
    this.eyebrow,
    this.actions,
    this.showBackButton = true,
    this.onBack,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset,
    this.maxWidth,
  });

  final String? title;
  final String? eyebrow;
  final List<Widget>? actions;
  final bool showBackButton;
  final VoidCallback? onBack;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool? resizeToAvoidBottomInset;

  /// Overrides the content/header width cap. Defaults to the responsive
  /// [BreakpointContext.contentMaxWidth].
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null;
    final effectiveMaxWidth = maxWidth ?? context.contentMaxWidth;
    return Scaffold(
      backgroundColor: appPageBackground,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      appBar: hasHeader
          ? PreferredSize(
              preferredSize: Size.fromHeight(
                MediaQuery.of(context).padding.top +
                    (eyebrow == null ? 60 : 72),
              ),
              child: _ClampedHeader(
                title: title!,
                eyebrow: eyebrow,
                actions: actions,
                showBackButton: showBackButton,
                onBack: onBack,
                maxWidth: effectiveMaxWidth,
              ),
            )
          : null,
      body: AppGridBackground(
        child: SafeArea(
          top: !hasHeader,
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding =
                  constraints.maxWidth > effectiveMaxWidth
                      ? (constraints.maxWidth - effectiveMaxWidth) / 2
                      : 0.0;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: body,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ClampedHeader extends StatelessWidget {
  const _ClampedHeader({
    required this.title,
    required this.eyebrow,
    required this.actions,
    required this.showBackButton,
    required this.onBack,
    required this.maxWidth,
  });

  final String title;
  final String? eyebrow;
  final List<Widget>? actions;
  final bool showBackButton;
  final VoidCallback? onBack;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: appPageBackground,
            border: Border(bottom: BorderSide(color: appBorder)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: Row(
                children: [
                  if (showBackButton) ...[
                    _HeaderIconAction(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: onBack ?? () => _defaultBack(context),
                    ),
                    const SizedBox(width: appSpaceSm),
                  ] else
                    const SizedBox(width: appSpaceSm),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (eyebrow != null) ...[
                            Text(
                              eyebrow!.toUpperCase(),
                              style: const TextStyle(
                                color: appPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: appText,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (actions != null)
                    for (final action in actions!) ...[
                      action,
                      const SizedBox(width: 6),
                    ]
                  else
                    const SizedBox(width: appSpaceSm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void _defaultBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }
}

/// Compact 40×40 outlined icon button matched to the shell's header buttons.
/// Use for header actions (notifications, switch, overflow, back).
class _HeaderIconAction extends StatelessWidget {
  const _HeaderIconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(appRadiusMd),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: appSurface,
              borderRadius: BorderRadius.circular(appRadiusMd),
              border: Border.all(color: appBorder),
            ),
            child: Icon(icon, color: appText, size: 20),
          ),
        ),
      ),
    );
  }
}

/// Public version of [_HeaderIconAction] for screens that want to add custom
/// actions (e.g. a "save" or "menu" button) to the [AppMobileScaffold]
/// header. Kept here so feature screens don't reimplement the same chrome.
class AppHeaderActionButton extends StatelessWidget {
  const AppHeaderActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HeaderIconAction(icon: icon, tooltip: tooltip, onTap: onTap);
  }
}
