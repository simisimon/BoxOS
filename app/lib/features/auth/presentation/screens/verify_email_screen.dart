import 'package:app/core/errors/error_message.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/presentation/widgets/auth_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _tokenController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail ?? '';
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty || _isVerifying) return;
    setState(() => _isVerifying = true);
    try {
      await ref.read(authControllerProvider.notifier).verifyEmail(token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email verified. You can now sign in.')),
      );
      context.go('/login');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: 'Email verification failed'))),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _isResending) return;
    setState(() => _isResending = true);
    try {
      await ref.read(authControllerProvider.notifier).resendEmailVerification(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification email resent.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: 'Resend failed'))),
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthStage(
      title: 'Verify Email',
      eyebrow: 'Activation',
      headline: 'Prove the inbox. Unlock the account.',
      description:
          'Enter the verification token from your email, or resend the message if the first delivery missed you.',
      accentColor: const Color(0xFF5FB2FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthFieldGroup(
            icon: Icons.verified_outlined,
            title: 'Verification Token',
            subtitle: 'Paste the token from the email to activate account access.',
            child: Column(
              children: [
                TextField(
                  controller: _tokenController,
                  decoration: const InputDecoration(labelText: 'Verification Token', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _isVerifying ? null : _verify,
                  child: _isVerifying
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Verify Email'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AuthFieldGroup(
            icon: Icons.outgoing_mail,
            title: 'Resend Verification Email',
            subtitle: 'If needed, trigger a fresh verification email to the address below.',
            accentColor: const Color(0xFFB98CFF),
            child: Column(
              children: [
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: _isResending ? null : _resend,
                  child: _isResending
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Resend Verification Email'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }
}
