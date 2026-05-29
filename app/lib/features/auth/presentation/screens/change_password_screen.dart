import 'dart:ui';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _logoutOtherSessions = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value, String label) {
    if ((value ?? '').isEmpty) {
      return '$label is required';
    }
    return null;
  }

  String? _newPasswordValidator(String? value) {
    final password = value ?? '';
    if (password.isEmpty) {
      return 'New password is required';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  String? _confirmValidator(String? value) {
    if ((value ?? '') != _newPasswordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || _isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .changePassword(
            currentPassword: _currentPasswordController.text,
            newPassword: _newPasswordController.text,
            logoutOtherSessions: _logoutOtherSessions,
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated successfully.')),
      );
      context.go('/home');
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to change password'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appPageBackground,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              appPageBackground,
              appPageBackgroundSoft,
              Color(0xFF0B1320),
            ],
          ),
        ),
        child: SafeArea(
          child: MobileScrollableContent(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SecurityHero(
                    title: 'Change Password',
                    headline: 'Rotate access with confidence.',
                    description:
                        'Update your credentials and optionally clear other active sessions from one cleaner security surface.',
                    accentColor: appPrimary,
                  ),
                  const SizedBox(height: 16),
                  const _SectionTitle(
                    eyebrow: 'Security',
                    title: 'Protect your account',
                    subtitle:
                        'Use a strong new password and decide whether to sign out other active devices.',
                  ),
                  const SizedBox(height: 12),
                  _FieldCard(
                    icon: Icons.lock_outline,
                    title: 'Current Password',
                    subtitle:
                        'Confirm the current credential before rotating access.',
                    child: TextFormField(
                      controller: _currentPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          _requiredValidator(value, 'Current password'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FieldCard(
                    icon: Icons.enhanced_encryption_outlined,
                    title: 'New Password',
                    subtitle: 'Choose a password with at least 8 characters.',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'New Password',
                            border: OutlineInputBorder(),
                          ),
                          validator: _newPasswordValidator,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Confirm New Password',
                            border: OutlineInputBorder(),
                          ),
                          validator: _confirmValidator,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ToggleCard(
                    icon: Icons.devices_outlined,
                    title: 'Log out other devices',
                    subtitle:
                        'End other sessions after the password change completes.',
                    value: _logoutOtherSessions,
                    onChanged: _isSubmitting
                        ? null
                        : (value) {
                            setState(() => _logoutOtherSessions = value);
                          },
                    accentColor: appPrimary,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Update Password'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityHero extends StatelessWidget {
  const _SecurityHero({
    required this.title,
    required this.headline,
    required this.description,
    required this.accentColor,
    this.danger = false,
  });

  final String title;
  final String headline;
  final String description;
  final Color accentColor;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withOpacity(0.24), appSurface, appSurfaceAlt],
        ),
        border: Border.all(color: appBorder),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.14),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -12,
            child: _GlowOrb(color: accentColor, size: 84),
          ),
          Positioned(
            right: 38,
            bottom: -28,
            child: _GlowOrb(color: appPrimary.withOpacity(0.6), size: 88),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _HeaderIconButton(),
                  const SizedBox(width: 8),
                  _HeroPill(label: title, color: accentColor),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: appPrimary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                headline,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 0.96,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: appMutedText,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: appPrimary,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 0.96,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: appSubtleText,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: appBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccentBadge(icon: icon, color: appPrimary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appSubtleText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: appBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccentBadge(icon: icon, color: accentColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appSubtleText,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: appSurfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: appSurfaceAlt),
          ),
          child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.95), color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}

class _AccentBadge extends StatelessWidget {
  const _AccentBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.28), color.withOpacity(0.12)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}
