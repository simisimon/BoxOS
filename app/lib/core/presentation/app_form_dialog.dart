import 'package:app/core/presentation/app_chrome.dart';
import 'package:flutter/material.dart';

/// Shared frame for the class and WOD forms: same size, header and action
/// bar everywhere, only [child] differs. The size stays fixed whatever the
/// content; long forms scroll between header and actions.
class AppFormDialog extends StatelessWidget {
  const AppFormDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    required this.actions,
    this.leading,
  });

  static const width = 520.0;
  static const height = 640.0;

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;

  /// Left of the action bar, e.g. a delete icon.
  final Widget? leading;

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

    return Dialog(
      backgroundColor: appSurface,
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: appText,
                      fontWeight: FontWeight.w800,
                    ),
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
            const Divider(height: 1, color: appBorder),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: child,
              ),
            ),
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
        ),
      ),
    );
  }
}
