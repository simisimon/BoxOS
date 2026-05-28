import 'package:app/core/errors/error_message.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/presentation/widgets/auth_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.initialToken});

  final String? initialToken;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _logoutOtherSessions = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _tokenController.text = widget.initialToken ?? '';
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _required(String? value, String label) {
    if ((value ?? '').trim().isEmpty) return '$label is required';
    return null;
  }

  String? _passwordValidator(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'New password is required';
    if (password.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  String? _confirmValidator(String? value) {
    if ((value ?? '') != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(authControllerProvider.notifier).resetPassword(
            token: _tokenController.text.trim(),
            newPassword: _passwordController.text,
            logoutOtherSessions: _logoutOtherSessions,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. You can now sign in.')),
      );
      context.go('/login');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: 'Password reset failed'))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthStage(
      title: 'Reset Password',
      eyebrow: 'Recovery',
      headline: 'Reclaim the account. Close the gap.',
      description:
          'Use the reset token, choose a new password, and optionally terminate other active sessions in one pass.',
      accentColor: const Color(0xFF7EE7C6),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthFieldGroup(
              icon: Icons.restart_alt_rounded,
              title: 'Password Recovery',
              subtitle: 'Complete the recovery flow with your token and fresh credentials.',
              accentColor: const Color(0xFF7EE7C6),
              child: Column(
                children: [
                  TextFormField(
                    controller: _tokenController,
                    decoration: const InputDecoration(labelText: 'Reset Token', border: OutlineInputBorder()),
                    validator: (value) => _required(value, 'Reset token'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder()),
                    validator: _passwordValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Confirm New Password', border: OutlineInputBorder()),
                    validator: _confirmValidator,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Log out other devices'),
                subtitle: const Text('Recommended after recovering your password.'),
                value: _logoutOtherSessions,
                onChanged: _isSubmitting ? null : (value) => setState(() => _logoutOtherSessions = value),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }
}
