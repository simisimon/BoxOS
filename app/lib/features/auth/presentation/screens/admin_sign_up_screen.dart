import 'package:app/core/errors/error_message.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/presentation/widgets/auth_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminSignUpScreen extends ConsumerStatefulWidget {
  const AdminSignUpScreen({super.key});

  @override
  ConsumerState<AdminSignUpScreen> createState() => _AdminSignUpScreenState();
}

class _AdminSignUpScreenState extends ConsumerState<AdminSignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) return 'Enter a valid email';
    return null;
  }

  String? _passwordValidator(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required';
    if (password.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  String? _confirmValidator(String? value) {
    if ((value ?? '') != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _onSubmit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(authControllerProvider.notifier).signUpAdmin(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin account created. Verify your email, then create your gym.')),
      );
      context.go('/verify-email?email=${Uri.encodeComponent(_emailController.text.trim())}');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: 'Admin sign up failed'))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthStage(
      title: 'Create Admin Account',
      eyebrow: 'Operator Setup',
      headline: 'Build the box before you run it.',
      description:
          'Use the admin path when you will manage a gym, approve members, and operate scheduling and programming.',
      accentColor: const Color(0xFFB98CFF),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthFieldGroup(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Admin Registration',
              subtitle: 'Create the account that owns gym setup and operational permissions.',
              accentColor: const Color(0xFFB98CFF),
              child: Column(
                children: [
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                    validator: _emailValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    validator: _passwordValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Confirm Password', border: OutlineInputBorder()),
                    validator: _confirmValidator,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const AuthNoteCard(
              title: 'Admin path',
              body: 'After verification you can create a gym, review join requests, and assign roles from inside BoxOS.',
              accentColor: Color(0xFFB98CFF),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isSubmitting ? null : _onSubmit,
              child: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create Admin Account'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _isSubmitting ? null : () => context.go('/sign-up'),
              child: const Text('Back to athlete sign up'),
            ),
          ],
        ),
      ),
    );
  }
}
