import 'package:app/core/presentation/app_chrome.dart';
import 'package:flutter/material.dart';

/// Unified empty / error / loading states. Every list, rail, and panel in the
/// app should funnel through these so the silhouette of a "nothing here yet"
/// surface is identical app-wide.

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  })  : _isError = false;

  /// Convenience constructor for error states. Tints the badge and message in
  /// the danger tone but keeps the silhouette identical to a regular empty.
  const AppEmptyState.error({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  })  : icon = Icons.error_outline_rounded,
        _isError = true;

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final bool _isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _isError ? appDanger : appPrimary;
    final padding = compact
        ? const EdgeInsets.all(appSpaceLg)
        : const EdgeInsets.all(appSpaceXl);

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: appPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(appRadiusMd),
              color: accent.withValues(alpha: 0.14),
              border: Border.all(color: accent.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(height: appSpaceMd),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: appText,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: appSubtleText,
                height: 1.45,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: appSpaceLg),
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.height = 180});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation(appPrimary),
          ),
        ),
      ),
    );
  }
}
