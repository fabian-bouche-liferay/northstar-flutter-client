import 'dart:convert';

import 'package:http/http.dart' as http;

import 'connection.dart';
import 'session.dart';

class LiferayException implements Exception {
  LiferayException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}

/// No usable session: the user must sign in (again).
class NotSignedInException extends LiferayException {
  NotSignedInException([String message = 'Not signed in'])
    : super(message, 401);
}

/// Minimal Liferay headless client. Authenticates either a signed-in user
/// (OAuth 2 authorization code + PKCE, with refresh tokens) or the app itself
/// (client credentials), depending on [Connection.authMode].
class LiferayClient {
  LiferayClient({
    http.Client? httpClient,
    this.resolve,
    Connection? connection,
    String? clientId,
    String? clientSecret,
    Session? session,
    this.onSessionChanged,
  }) : _http = httpClient ?? http.Client(),
       _session = session, // ignore: prefer_initializing_formals
       _connection = (connection ?? Connection.fromBuild()).copyWith(
         clientId: clientId,
         clientSecret: clientSecret,
         // An explicit secret (tools, integration tests) means client
         // credentials.
         authMode: clientSecret?.isNotEmpty == true
             ? AuthMode.clientCredentials
             : null,
       );

  final http.Client _http;

  /// Test hook: overrides how API paths are turned into URLs.
  final Uri Function(String)? resolve;

  /// Called when the user session is created, refreshed or dropped (to
  /// persist it).
  void Function(Session?)? onSessionChanged;

  Connection _connection;
  Session? _session;

  Connection get connection => _connection;

  /// The signed-in user (authorization code flow), if any.
  Session? get session => _session;

  /// Switches server, space or OAuth 2 client; the next call gets a new token.
  /// The user session is kept only if [keepSession].
  void connect(Connection connection, {bool keepSession = false}) {
    _connection = connection;
    _appToken = null;
    _pendingToken = null;
    if (!keepSession) _setSession(null);
  }

  void _setSession(Session? session) {
    _session = session;
    onSessionChanged?.call(session);
  }

  Uri url(String pathAndQuery) =>
      resolve?.call(pathAndQuery) ?? _connection.api(pathAndQuery);

  // Client credentials token (app identity).
  String? _appToken;
  DateTime _appTokenExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const _commonHeaders = {
    'Accept': 'application/json',
    // Avoids the ngrok free-tier interstitial page.
    'ngrok-skip-browser-warning': '1',
  };

  Future<String>? _pendingToken;

  /// Returns a valid access token; concurrent callers share one request.
  /// Throws [NotSignedInException] when a user session is needed but missing
  /// or can no longer be refreshed.
  Future<String> accessToken() {
    if (_connection.authMode == AuthMode.clientCredentials) {
      if (_appToken != null && DateTime.now().isBefore(_appTokenExpiresAt)) {
        return Future.value(_appToken!);
      }
    } else {
      final session = _session;
      if (session == null) return Future.error(NotSignedInException());
      if (!session.isExpired) return Future.value(session.accessToken);
    }
    return _pendingToken ??= _requestToken().whenComplete(
      () => _pendingToken = null,
    );
  }

  Future<String> _requestToken() async {
    if (_connection.authMode == AuthMode.clientCredentials) {
      final json = await _tokenRequest({
        'grant_type': 'client_credentials',
        'client_id': _connection.clientId,
        'client_secret': _connection.clientSecret,
      });
      _appToken = json['access_token'] as String;
      final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 600;
      _appTokenExpiresAt = DateTime.now().add(
        Duration(seconds: expiresIn - 30),
      );
      return _appToken!;
    }
    final refreshToken = _session?.refreshToken;
    if (refreshToken == null) {
      _setSession(null);
      throw NotSignedInException('Session expired');
    }
    try {
      final json = await _tokenRequest({
        'grant_type': 'refresh_token',
        'client_id': _connection.clientId,
        'refresh_token': refreshToken,
      });
      final refreshed = Session.fromTokenResponse({
        'refresh_token': refreshToken, // kept if Liferay does not rotate it
        ...json,
      });
      _setSession(refreshed);
      return refreshed.accessToken;
    } on LiferayException catch (e) {
      // 400 invalid_grant: refresh token expired or revoked.
      if (e.statusCode == 400 || e.statusCode == 401) {
        _setSession(null);
        throw NotSignedInException('Session expired');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _tokenRequest(Map<String, String> body) async {
    final response = await _http.post(
      url('/o/oauth2/token'),
      headers: _commonHeaders,
      body: body,
    );
    if (response.statusCode != 200) {
      throw LiferayException(
        'OAuth2 token request failed: ${response.body}',
        response.statusCode,
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Authorization code flow, last step: exchanges the code returned to
  /// [redirectUri] (with the PKCE [codeVerifier]) for the user's tokens.
  Future<Session> signInWithCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final json = await _tokenRequest({
      'grant_type': 'authorization_code',
      'client_id': _connection.clientId,
      'code': code,
      'code_verifier': codeVerifier,
      'redirect_uri': redirectUri,
    });
    final session = Session.fromTokenResponse(json);
    _setSession(session);
    return session;
  }

  /// Forgets the user session (tokens are not revoked server side).
  void signOut() => _setSession(null);

  Future<Map<String, dynamic>> getJson(String pathAndQuery) async {
    for (var attempt = 0; ; attempt++) {
      final token = await accessToken();
      final response = await _http.get(
        url(pathAndQuery),
        headers: {..._commonHeaders, 'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 401 && attempt == 0) {
        // Token revoked or expired: get a new one and retry once.
        _appToken = null;
        final s = _session;
        if (s != null) {
          _session = Session(
            accessToken: s.accessToken,
            refreshToken: s.refreshToken,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
            userId: s.userId,
            userName: s.userName,
          );
        }
        continue;
      }
      if (response.statusCode != 200) {
        throw LiferayException(
          'GET $pathAndQuery failed: ${response.body}',
          response.statusCode,
        );
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }
  }

  static String _query(Map<String, String?> params) => params.entries
      .where((e) => e.value != null)
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value!)}')
      .join('&');

  /// Returns every entry of a space-scoped object definition
  /// (`/o/c/{restPath}/scopes/{spaceErc}`), following pagination.
  ///
  /// [filter] is an OData filter, e.g. `dateModified gt 2026-10-13T15:41:47Z`.
  /// [fields] limits the returned properties (lightweight checks); otherwise
  /// full entries are returned, without their `actions`.
  Future<List<Map<String, dynamic>>> fetchAllEntries(
    String restPath, {
    String? spaceErc,
    String? filter,
    String? fields,
    int pageSize = 100,
  }) async {
    final items = <Map<String, dynamic>>[];
    for (var page = 1; ; page++) {
      final json = await getJson(
        '/o/c/$restPath/scopes/${spaceErc ?? _connection.spaceErc}?${_query({'page': '$page', 'pageSize': '$pageSize', 'filter': filter, 'fields': fields, 'restrictFields': fields == null ? 'actions' : null})}',
      );
      items.addAll((json['items'] as List).cast<Map<String, dynamic>>());
      final lastPage = (json['lastPage'] as num?)?.toInt() ?? 1;
      if (page >= lastPage) return items;
    }
  }

  /// Returns one entry by external reference code, or `null` when it does
  /// not exist anymore (404).
  Future<Map<String, dynamic>?> fetchEntry(
    String restPath,
    String erc, {
    String? spaceErc,
    String? fields,
  }) async {
    try {
      return await getJson(
        '/o/c/$restPath/scopes/${spaceErc ?? _connection.spaceErc}'
        '/by-external-reference-code/${Uri.encodeComponent(erc)}?${_query({'fields': fields, 'restrictFields': fields == null ? 'actions' : null})}',
      );
    } on LiferayException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Returns the subset of [ercs] that still exist, using
  /// `externalReferenceCode in (...)` filters in batches.
  Future<Set<String>> existingErcs(
    String restPath,
    Iterable<String> ercs, {
    String? spaceErc,
    int batchSize = 50,
  }) async {
    final all = ercs.toList();
    final batches = [
      for (var i = 0; i < all.length; i += batchSize)
        all.sublist(i, (i + batchSize).clamp(0, all.length)),
    ];
    final results = await Future.wait(
      batches.map(
        (batch) => fetchAllEntries(
          restPath,
          spaceErc: spaceErc,
          fields: 'externalReferenceCode',
          pageSize: batchSize,
          filter:
              'externalReferenceCode in '
              '(${batch.map((e) => "'${e.replaceAll("'", "''")}'").join(',')})',
        ),
      ),
    );
    return {
      for (final items in results)
        for (final item in items) item['externalReferenceCode'] as String,
    };
  }

  /// Full-text search with the Liferay search API, optionally through a
  /// Search Blueprint. Each item carries `title`, `score`, a highlighted
  /// `description` and the entry ERC in `embedded.externalReferenceCode`.
  Future<List<Map<String, dynamic>>> search(
    String query, {
    String? blueprintErc,
    int pageSize = 50,
  }) async {
    final json = await getJson(
      '/o/search/v1.0/search?${_query({'search': query, 'blueprintExternalReferenceCode': blueprintErc, 'pageSize': '$pageSize', 'nestedFields': 'embedded', 'fields': 'title,score,description,entryClassName,'
          'embedded.externalReferenceCode'})}',
    );
    return (json['items'] as List).cast<Map<String, dynamic>>();
  }

  /// Search Blueprints visible to this client.
  Future<List<Map<String, dynamic>>> searchBlueprints() async {
    final json = await getJson(
      '/o/search-experiences-rest/v1.0/sxp-blueprints?pageSize=100',
    );
    return (json['items'] as List).cast<Map<String, dynamic>>();
  }

  void close() => _http.close();
}
