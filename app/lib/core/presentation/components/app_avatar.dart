import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/routing/env.dart';
import 'package:flutter/material.dart';

/// Renders a user avatar: profile photo if available, initials fallback.
///
/// Accepts the server-relative path that the backend hands out
/// (e.g. `/uploads/avatars/abc.jpg`) and rebases it against the API host
/// configured at compile time. Absolute URLs are passed through unchanged so
/// the same widget can render external images later without a refactor.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.displayName,
    this.imageUrl,
    this.size = 40,
    this.onTap,
    this.background,
    this.foreground,
  });

  final String displayName;
  final String? imageUrl;
  final double size;
  final VoidCallback? onTap;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveUrl(imageUrl);
    final bg = background ?? appPrimarySoft;
    final fg = foreground ?? appText;
    final child = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: appPrimaryHairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: resolved == null
          ? Center(
              child: Text(
                _initials(displayName),
                style: TextStyle(
                  color: fg,
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            )
          : Image.network(
              resolved,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Center(
                child: Text(
                  _initials(displayName),
                  style: TextStyle(
                    color: fg,
                    fontSize: size * 0.36,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: appSurfaceAlt,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: size * 0.4,
                    height: size * 0.4,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(appPrimary),
                    ),
                  ),
                );
              },
            ),
    );

    if (onTap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }

  static String? _resolveUrl(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }
    final base = AppEnv.current.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '$base$path';
  }

  static String _initials(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'U';
    final parts = normalized.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}
