import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/presentation/widgets/auth_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _AuthCallbackStatus { loading, success, error }

class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({
    super.key,
    required this.type,
    required this.tokenHash,
    this.errorDescription,
  });

  final String? type;
  final String? tokenHash;
  final String? errorDescription;

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  _AuthCallbackStatus _status = _AuthCallbackStatus.loading;
  String _message = 'Processing sign-in link...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleCallback());
  }

  Future<void> _handleCallback() async {
    final type = widget.type?.trim() ?? '';
    final tokenHash = widget.tokenHash?.trim() ?? '';
    final authError = widget.errorDescription?.trim();

    if (authError != null && authError.isNotEmpty) {
      _setError(authError);
      return;
    }
    if (type.isEmpty || tokenHash.isEmpty) {
      _setError('The authentication link is missing required parameters.');
      return;
    }
    if (type == 'recovery') {
      if (!mounted) return;
      context.go('/reset-password?token=${Uri.encodeComponent(tokenHash)}');
      return;
    }
    if (type != 'signup' && type != 'email') {
      _setError('Unsupported authentication link type: $type');
      return;
    }

    try {
      await ref
          .read(authControllerProvider.notifier)
          .verifyEmail(token: tokenHash, type: type);
      if (!mounted) return;
      setState(() {
        _status = _AuthCallbackStatus.success;
        _message = 'Email verified. You can now sign in.';
      });
    } catch (error) {
      _setError(
        errorMessageFrom(error, fallback: 'Authentication link failed'),
      );
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _status = _AuthCallbackStatus.error;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _status == _AuthCallbackStatus.loading;
    final isError = _status == _AuthCallbackStatus.error;
    final icon = isLoading
        ? const SizedBox(
            height: 56,
            width: 56,
            child: CircularProgressIndicator(strokeWidth: 3),
          )
        : Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 56,
            color: isError ? appDanger : appPrimary,
          );

    return AuthStage(
      title: 'Auth Callback',
      eyebrow: 'Magic Link',
      headline: isLoading
          ? 'Verifying the link.'
          : isError
          ? 'The link needs attention.'
          : 'You are verified.',
      description:
          'BoxOS is interpreting the authentication callback and routing you into the correct next step.',
      accentColor: isError ? appDanger : appPrimary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: icon),
          const SizedBox(height: 16),
          Text(
            _message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!isLoading) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/login'),
              child: const Text('Back to Sign In'),
            ),
          ],
        ],
      ),
    );
  }
}
