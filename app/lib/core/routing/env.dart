class AppEnv {
  const AppEnv({
    required this.environment,
    required this.apiBaseUrl,
    required this.authRedirectUrl,
  });

  final String environment;
  final String apiBaseUrl;
  final String authRedirectUrl;

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
  );
}
