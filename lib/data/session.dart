import 'dart:convert';

/// A signed-in Liferay user (authorization code flow): tokens and identity.
class Session {
  const Session({
    required this.accessToken,
    required this.expiresAt,
    required this.userId,
    required this.userName,
    this.refreshToken,
  });

  /// Builds a session from a `/o/oauth2/token` response. Liferay access
  /// tokens are JWTs whose `sub` claim is the user id.
  factory Session.fromTokenResponse(Map<String, dynamic> json) {
    final accessToken = json['access_token'] as String;
    final claims = jwtClaims(accessToken);
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 600;
    return Session(
      accessToken: accessToken,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn - 30)),
      userId: '${claims['sub'] ?? ''}',
      userName: '${claims['username'] ?? claims['sub'] ?? ''}',
    );
  }

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String?,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    userId: json['userId'] as String,
    userName: json['userName'] as String,
  );

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  /// Liferay user id (JWT `sub`): partitions the offline cache.
  final String userId;
  final String userName;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'userId': userId,
    'userName': userName,
  };
}

/// Decodes the payload of a JWT (no signature check: the token comes straight
/// from the Liferay token endpoint over HTTPS). Empty if not a JWT.
Map<String, dynamic> jwtClaims(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return const {};
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    return jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return const {};
  }
}
