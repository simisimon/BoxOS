import 'package:app/core/errors/error_message.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/presentation/widgets/auth_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
    if (password.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;
    final errorText = authState.hasError && authState.error != null
        ? errorMessageFrom(authState.error!, fallback: 'Login failed')
        : null;

    return AuthStage(
      title: 'Sign In',
      headline: 'Step back into the box.',
      description:
          'Open your schedule, log training, and manage the gym from one sharp mobile entry point.',
      showBrandHero: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthFieldGroup(
              icon: Icons.mail_outline,
              title: 'Email & Password',
              subtitle: 'Use the credentials linked to your BoxOS account.',
              child: Column(
                children: [
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: _emailValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    validator: _passwordValidator,
                  ),
                ],
              ),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 12),
              AuthInlineError(message: errorText),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () {
                      final isValid =
                          _formKey.currentState?.validate() ?? false;
                      if (!isValid) return;
                      ref
                          .read(authControllerProvider.notifier)
                          .signIn(
                            email: _emailController.text.trim(),
                            password: _passwordController.text,
                          );
                    },
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign In'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: isLoading ? null : () => context.go('/sign-up'),
              child: const Text('Create Account'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: isLoading ? null : () => context.go('/admin-sign-up'),
              child: const Text('Create Box'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () => context.go('/forgot-password'),
              child: const Text('Forgot Password?'),
            ),
          ],
        ),
      ),
    );
  }
}
