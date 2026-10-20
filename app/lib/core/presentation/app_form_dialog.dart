import 'package:app/core/presentation/app_chrome.dart';
import 'package:flutter/material.dart';

/// Shared frame for every dialog in the app: same size, header and action
/// bar everywhere, only [child] differs. The size stays fixed whatever the
/// content; long content scrolls between header and actions. Short
/// confirmations pass [fitContent] to keep the look at their own height.
class AppFormDialog extends StatelessWidget {
  const AppFormDialog({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    required this.actions,
    this.leading,
    this.fitContent = false,
  });

  static const width = 520.0;
  static const height = 640.0;

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;

  /// Left of the action bar, e.g. a delete icon.
  final Widget? leading;

  /// Shrinks the height to the content (at most [height]), for confirmations.
  final bool fitContent;

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
        height: fitContent ? null : height,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: height),
          child: Column(
            mainAxisSize: fitContent ? MainAxisSize.min : MainAxisSize.max,
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
              Flexible(
                fit: fitContent ? FlexFit.loose : FlexFit.tight,
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
      ),
    );
  }
}

/// Yes/no question in the shared dialog frame. Resolves to true on confirm.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppFormDialog(
      title: title,
      fitContent: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: appDanger)
              : null,
          child: Text(confirmLabel),
        ),
      ],
      child: Text(
        message,
        style: Theme.of(
          dialogContext,
        ).textTheme.bodyMedium?.copyWith(color: appText, height: 1.45),
      ),
    ),
  );
  return confirmed ?? false;
}
