import '../config.dart';

/// How the app authenticates against Liferay.
enum AuthMode {
  /// Each user signs in with their Liferay account (authorization code +
  /// PKCE, public client, no secret). Content follows the user's permissions.
  authorizationCode,

  /// The app uses a client ID + secret (service account, for tests).
  clientCredentials,
}

/// How to reach Liferay: server, CMS space and OAuth 2 clients.
///
/// The two OAuth 2 clients are kept separately — the public client used for
/// user sign-in and the service account (ID + secret) — so switching mode
/// never loses the other one; [authMode] selects the active client.
///
/// Defaults come from the build (`--dart-define-from-file`); users can
/// override them at runtime in the Connection settings, so a build shared
/// with colleagues does not need to embed any client.
class Connection {
  const Connection.raw({
    required this.liferayUrl,
    required this.spaceErc,
    required this.authMode,
    required this.userClientId,
    required this.serviceClientId,
    required this.serviceClientSecret,
  });

  /// [clientId] / [clientSecret] set the client of [authMode]; the explicit
  /// per-mode values take precedence.
  factory Connection({
    String liferayUrl = '',
    String spaceErc = 'NMG-KNOWLEDGE',
    AuthMode authMode = AuthMode.authorizationCode,
    String clientId = '',
    String clientSecret = '',
    String? userClientId,
    String? serviceClientId,
    String? serviceClientSecret,
  }) {
    final isUser = authMode == AuthMode.authorizationCode;
    return Connection.raw(
      liferayUrl: liferayUrl,
      spaceErc: spaceErc,
      authMode: authMode,
      userClientId: userClientId ?? (isUser ? clientId : ''),
      serviceClientId: serviceClientId ?? (isUser ? '' : clientId),
      serviceClientSecret: serviceClientSecret ?? (isUser ? '' : clientSecret),
    );
  }

  factory Connection.fromBuild() => Connection(
    liferayUrl: AppConfig.liferayUrl,
    spaceErc: AppConfig.spaceErc,
    clientId: AppConfig.clientId,
    clientSecret: AppConfig.clientSecret,
    authMode:
        _authMode(AppConfig.authMode) ??
        (AppConfig.clientSecret.isEmpty
            ? AuthMode.authorizationCode
            : AuthMode.clientCredentials),
  );

  static AuthMode? _authMode(String? name) => AuthMode.values.asNameMap()[name];

  /// Reads the stored settings; also accepts the former single-client format
  /// (`clientId` / `clientSecret`, applied to the stored mode).
  factory Connection.fromJson(Map<String, dynamic> json) => Connection(
    liferayUrl: json['liferayUrl'] as String? ?? '',
    spaceErc: json['spaceErc'] as String? ?? 'NMG-KNOWLEDGE',
    authMode:
        _authMode(json['authMode'] as String?) ?? AuthMode.authorizationCode,
    clientId: json['clientId'] as String? ?? '',
    clientSecret: json['clientSecret'] as String? ?? '',
    userClientId: json['userClientId'] as String?,
    serviceClientId: json['serviceClientId'] as String?,
    serviceClientSecret: json['serviceClientSecret'] as String?,
  );

  /// Liferay base URL; empty means "same origin as the web app" (proxy).
  final String liferayUrl;
  final String spaceErc;
  final AuthMode authMode;

  /// Public client (no secret) used for user sign-in.
  final String userClientId;

  /// Service account client (client credentials).
  final String serviceClientId;
  final String serviceClientSecret;

  /// Client of the active [authMode].
  String get clientId =>
      authMode == AuthMode.authorizationCode ? userClientId : serviceClientId;

  /// Secret of the active [authMode] (none for user sign-in).
  String get clientSecret =>
      authMode == AuthMode.authorizationCode ? '' : serviceClientSecret;

  /// Enough to talk to Liferay: a client ID, plus a secret for client
  /// credentials. The authorization code flow needs an explicit server URL.
  bool get hasCredentials => switch (authMode) {
    AuthMode.clientCredentials =>
      clientId.isNotEmpty && clientSecret.isNotEmpty,
    AuthMode.authorizationCode => clientId.isNotEmpty && _base.isNotEmpty,
  };

  /// Same server, space and active OAuth 2 client: a user session stays valid.
  bool sameClient(Connection other) =>
      sameSource(other) &&
      clientId == other.clientId &&
      authMode == other.authMode;

  /// Same server and space: the offline copy stays valid.
  bool sameSource(Connection other) =>
      _base == other._base && spaceErc == other.spaceErc;

  String get _base => liferayUrl.trim().replaceFirst(RegExp(r'/+$'), '');

  /// Normalized Liferay URL (no trailing slash; empty: same origin).
  String get baseUrl => _base;

  Uri api(String pathAndQuery) => _base.isEmpty
      ? Uri.base.resolve(pathAndQuery)
      : Uri.parse('$_base$pathAndQuery');

  /// [clientId] / [clientSecret] change the client of the (new) active mode.
  Connection copyWith({
    String? liferayUrl,
    String? spaceErc,
    AuthMode? authMode,
    String? clientId,
    String? clientSecret,
    String? userClientId,
    String? serviceClientId,
    String? serviceClientSecret,
  }) {
    final mode = authMode ?? this.authMode;
    final isUser = mode == AuthMode.authorizationCode;
    return Connection.raw(
      liferayUrl: liferayUrl ?? this.liferayUrl,
      spaceErc: spaceErc ?? this.spaceErc,
      authMode: mode,
      userClientId:
          userClientId ?? (isUser ? clientId : null) ?? this.userClientId,
      serviceClientId:
          serviceClientId ?? (isUser ? null : clientId) ?? this.serviceClientId,
      serviceClientSecret:
          serviceClientSecret ??
          (isUser ? null : clientSecret) ??
          this.serviceClientSecret,
    );
  }

  Map<String, dynamic> toJson() => {
    'liferayUrl': liferayUrl,
    'spaceErc': spaceErc,
    'authMode': authMode.name,
    'userClientId': userClientId,
    'serviceClientId': serviceClientId,
    'serviceClientSecret': serviceClientSecret,
  };
}
