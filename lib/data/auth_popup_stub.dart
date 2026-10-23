/// No popup outside the web: returns null so the caller falls back to
/// flutter_web_auth_2 (Custom Tab on Android).
Future<String>? authenticateInPopup(String url) => null;
