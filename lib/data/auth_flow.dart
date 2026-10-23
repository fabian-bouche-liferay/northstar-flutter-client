import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'auth_popup.dart';
import 'liferay_client.dart';
import 'session.dart';

/// Custom URL scheme of the Android redirect (`nmgkb://oauth2`), declared in
/// AndroidManifest.xml and registered as a callback URI in Liferay.
const mobileCallbackScheme = 'nmgkb';

class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// OAuth 2 authorization code flow with PKCE (RFC 7636) against Liferay:
/// opens the Liferay sign-in page (centered popup on the web, Custom Tab on
/// Android),
/// receives the code on the redirect URI and exchanges it for tokens.
class AuthFlow {
  AuthFlow._();

  /// Must be registered as a callback URI of the Liferay OAuth 2 application.
  /// Web: `auth.html` next to the app (e.g. http://localhost:8765/auth.html);
  /// Android: `nmgkb://oauth2`.
  static String redirectUri() {
    if (!kIsWeb) return '$mobileCallbackScheme://oauth2';
    final base = Uri.base;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.port,
      path: base.resolve('auth.html').path,
    ).toString();
  }

  static Future<Session> signIn(LiferayClient client) async {
    final verifier = randomString(64);
    final state = randomString(24);
    final redirect = redirectUri();
    final authorize = client
        .url('/o/oauth2/authorize')
        .replace(
          queryParameters: {
            'response_type': 'code',
            'client_id': client.connection.clientId,
            'redirect_uri': redirect,
            'code_challenge': codeChallenge(verifier),
            'code_challenge_method': 'S256',
            'state': state,
          },
        );

    final String result;
    try {
      result =
          await (authenticateInPopup(authorize.toString()) ??
              FlutterWebAuth2.authenticate(
                url: authorize.toString(),
                callbackUrlScheme: mobileCallbackScheme,
              ));
    } on Exception catch (e) {
      throw AuthException(
        '$e'.contains('CANCELED') ? 'Sign-in cancelled.' : 'Sign-in failed: $e',
      );
    }
    final params = Uri.parse(result).queryParameters;
    if (params['error'] != null) {
      throw AuthException(
        'Liferay refused the sign-in: '
        '${params['error_description'] ?? params['error']}',
      );
    }
    if (params['state'] != state) {
      throw AuthException('Invalid sign-in response (state mismatch).');
    }
    final code = params['code'];
    if (code == null) throw AuthException('No authorization code received.');
    try {
      return await client.signInWithCode(
        code: code,
        codeVerifier: verifier,
        redirectUri: redirect,
      );
    } on LiferayException catch (e) {
      throw AuthException(switch (e.statusCode) {
        401 =>
          'Liferay refused the OAuth 2 client (401). The client '
              '"${client.connection.clientId}" requires a secret: use a public '
              'client (no client secret) allowing "Authorization Code PKCE".',
        400 =>
          'Liferay refused the authorization code (400). Check that '
              '$redirect is a callback URI of the OAuth 2 client.',
        _ => 'Sign-in failed: $e',
      });
    }
  }

  /// PKCE S256 challenge: BASE64URL(SHA256(verifier)) without padding.
  @visibleForTesting
  static String codeChallenge(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  /// URL-safe random string (PKCE verifier: 43..128 chars).
  @visibleForTesting
  static String randomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}
