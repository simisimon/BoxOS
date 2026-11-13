class AppEnv {
  const AppEnv({
    required this.environment,
    required this.apiBaseUrl,
    required this.authRedirectUrl,
    required this.inviteOnly,
  });

  final String environment;
  final String apiBaseUrl;
  final String authRedirectUrl;

  /// Invite-only builds (production) hide sign-up and password reset: accounts
  /// are created on the server with `python -m backend.manage create-user`.
  final bool inviteOnly;

  bool get isDev => environment == 'dev';

  static const AppEnv current = AppEnv(
    environment: String.fromEnvironment('ENV', defaultValue: 'dev'),
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    ),
    authRedirectUrl: String.fromEnvironment(
      'AUTH_REDIRECT_URL',
      defaultValue: 'boxos://auth-callback',
    ),
    inviteOnly: bool.fromEnvironment('INVITE_ONLY'),
  );
}
