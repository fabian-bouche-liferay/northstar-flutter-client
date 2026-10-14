import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'connection.dart';

/// Persists the connection entered in the settings on this device
/// (browser storage on the web, app preferences on Android). Not encrypted.
class ConnectionStore {
  ConnectionStore._();

  static const _key = 'settings.connection';

  /// The saved connection, or the build defaults.
  static Future<Connection> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    return saved == null
        ? Connection.fromBuild()
        : Connection.fromJson(jsonDecode(saved) as Map<String, dynamic>);
  }

  static Future<void> save(Connection connection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(connection.toJson()));
  }

  /// Back to the build defaults.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
