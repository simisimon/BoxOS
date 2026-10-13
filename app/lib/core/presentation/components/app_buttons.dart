import 'package:app/core/presentation/app_chrome.dart';
import 'package:flutter/material.dart';

/// Production-quality button primitives layered on top of the Material 3
/// button themes. These are not a re-skin — they exist so screens get
/// consistent sizing, busy-state spinners, and trailing-icon affordances
/// without repeating the same boilerplate.
///
/// Use [AppPrimaryButton] for the dominant action on a screen,
/// [AppSecondaryButton] for the secondary, and [AppGhostButton] for tertiary
/// flat actions inside cards. [AppDangerButton] is reserved for destructive
/// confirmations.

enum AppButtonSize { md, lg }

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.size = AppButtonSize.lg,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final AppButtonSize size;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final height = size == AppButtonSize.lg ? 52.0 : 44.0;
    return _ButtonShell(
      expand: expand,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: appPrimary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: appSurfaceAlt,
          disabledForegroundColor: appSubtleText,
          minimumSize: expand ? Size.fromHeight(height) : Size(0, height),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: appButtonShape(),
        ),
        child: _ButtonContent(label: label, icon: icon, busy: busy),
      ),
    );
  }
}

class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.size = AppButtonSize.lg,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final AppButtonSize size;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final height = size == AppButtonSize.lg ? 52.0 : 44.0;
    return _ButtonShell(
      expand: expand,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: appText,
          backgroundColor: appSurfaceAlt,
          side: const BorderSide(color: appBorderStrong),
          minimumSize: expand ? Size.fromHeight(height) : Size(0, height),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(appRadiusSm),
          ),
        ),
        child: _ButtonContent(label: label, icon: icon, busy: busy),
      ),
    );
  }
}

class AppGhostButton extends StatelessWidget {
  const AppGhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: appPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: _ButtonContent(label: label, icon: icon, busy: busy),
    );
  }
}

class AppDangerButton extends StatelessWidget {
  const AppDangerButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.size = AppButtonSize.lg,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final AppButtonSize size;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final height = size == AppButtonSize.lg ? 52.0 : 44.0;
    return _ButtonShell(
      expand: expand,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: appDanger,
          foregroundColor: Colors.white,
          disabledBackgroundColor: appSurfaceAlt,
          disabledForegroundColor: appSubtleText,
          minimumSize: expand ? Size.fromHeight(height) : Size(0, height),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: appButtonShape(),
        ),
        child: _ButtonContent(label: label, icon: icon, busy: busy),
      ),
    );
  }
}

class _ButtonShell extends StatelessWidget {
  const _ButtonShell({required this.expand, required this.child});

  final bool expand;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return expand ? SizedBox(width: double.infinity, child: child) : child;
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.busy,
  });

  final String label;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(Colors.white),
        ),
      );
    }
    if (icon == null) {
      return Text(label);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
    );
  }
}
