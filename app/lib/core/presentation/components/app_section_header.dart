import 'package:app/core/presentation/app_chrome.dart';
import 'package:flutter/material.dart';

/// Standardized section heading: small uppercase eyebrow + display title +
/// optional trailing action (e.g. "See all"). Provides the consistent rhythm
/// between sections that the previous one-off `_SectionHeading` widgets lost.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: appMono(
                      fontSize: 10.5,
                      letterSpacing: 1.6,
                      color: appPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: appText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
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
          if (trailing != null) ...[
            const SizedBox(width: appSpaceMd),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A compact "See all" / "Manage" link styled to live in the trailing slot of
/// an [AppSectionHeader].
class AppSectionLink extends StatelessWidget {
  const AppSectionLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(appRadiusPill),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: appPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: appPrimary,
            ),
          ],
        ),
      ),
    );
  }
}
