import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:web/web.dart';

/// Same key and message format as flutter_web_auth_2, written by
/// web/auth.html (postMessage to the opener, or localStorage when the opener
/// link was lost).
const _storageKey = 'flutter-web-auth-2';

const _width = 520;
const _height = 720;

/// Opens [url] in a popup centered on the app window and completes with the
/// callback URL received by auth.html. Returns null when the browser blocked
/// the popup, so the caller can fall back to a tab.
///
/// Must be called before any `await` in the click handler: browsers only
/// allow popups during a user gesture.
Future<String>? authenticateInPopup(String url) {
  window.localStorage.removeItem(_storageKey);

  final left = window.screenX + (window.outerWidth - _width) ~/ 2;
  final top = window.screenY + (window.outerHeight - _height) ~/ 2;
  final popup = window.open(
    url,
    'liferay-sign-in',
    'popup,width=$_width,height=$_height,left=$left,top=$top',
  );
  if (popup == null) return null;
  popup.focus();

  final completer = Completer<String>();
  late final StreamSubscription<MessageEvent> messages;
  Timer? poll;
  DateTime? closedAt;

  void finish({String? result, Object? error}) {
    if (completer.isCompleted) return;
    poll?.cancel();
    messages.cancel();
    if (result != null) {
      window.localStorage.removeItem(_storageKey);
      completer.complete(result);
    } else {
      completer.completeError(error!);
    }
  }

  messages = window.onMessage.listen((event) {
    if (event.origin != window.location.origin) return;
    final data = event.data.dartify();
    final message = data is Map ? data[_storageKey] : null;
    if (message is String) finish(result: message);
  });

  poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
    final stored = window.localStorage.getItem(_storageKey);
    if (stored != null) {
      finish(result: stored);
    } else if (popup.closed) {
      // auth.html closes the popup right after posting its message: give the
      // message (or the localStorage fallback) a moment to arrive.
      closedAt ??= DateTime.now();
      if (DateTime.now().difference(closedAt!) > const Duration(seconds: 2)) {
        finish(error: PlatformException(code: 'CANCELED'));
      }
    }
  });

  return completer.future;
}
