import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'connection.dart';
import 'session.dart';

/// Keeps the signed-in user's session on this device, so the app reopens
/// without a new sign-in (and works offline) while the refresh token is
/// valid. Bound to the connection it was obtained with. Not encrypted.
class SessionStore {
  SessionStore._();

  static const _key = 'auth.session';

  static Future<Session?> load(Connection connection) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final owner = Connection.fromJson(
      (json['connection'] as Map).cast<String, dynamic>(),
    );
    if (!owner.sameClient(connection)) return null;
    return Session.fromJson((json['session'] as Map).cast<String, dynamic>());
  }

  static Future<void> save(Connection connection, Session? session) async {
    final prefs = await SharedPreferences.getInstance();
    if (session == null) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(
      _key,
      jsonEncode({
        // Identity only: never store a client secret with the session.
        'connection': connection.copyWith(serviceClientSecret: '').toJson(),
        'session': session.toJson(),
      }),
    );
  }
}
