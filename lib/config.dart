/// Build-time defaults, injected with `--dart-define-from-file=…`. Users can
/// override them at runtime (see Connection / ConnectionStore).
class AppConfig {
  /// Liferay base URL. Empty means "same origin": the web app is served by
  /// `tool/serve.dart`, which proxies `/o/*` to Liferay (no CORS needed).
  static const liferayUrl = String.fromEnvironment('LIFERAY_URL');

  /// External reference code of the CMS Space (asset library).
  static const spaceErc = String.fromEnvironment(
    'SPACE_ERC',
    defaultValue: 'NMG-KNOWLEDGE',
  );

  static const clientId = String.fromEnvironment('OAUTH_CLIENT_ID');
  static const clientSecret = String.fromEnvironment('OAUTH_CLIENT_SECRET');

  /// `authorizationCode` or `clientCredentials`; empty: client credentials
  /// if a secret is provided, authorization code otherwise.
  static const authMode = String.fromEnvironment('AUTH_MODE');
}
