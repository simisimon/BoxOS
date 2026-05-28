import 'package:app/features/auth/presentation/widgets/auth_stage.dart';
import 'package:flutter/material.dart';

class AuthLoadingScreen extends StatelessWidget {
  const AuthLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthStage(
      title: 'Authenticating',
      eyebrow: 'Session',
      headline: 'Opening your workspace.',
      description: 'BoxOS is loading your account, memberships, and navigation context.',
      accentColor: Color(0xFF7EE7C6),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: SizedBox(
            height: 40,
            width: 40,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}
