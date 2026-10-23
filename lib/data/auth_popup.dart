/// Opens the Liferay sign-in page in a centered popup window on the web
/// (flutter_web_auth_2 opens a full browser tab). Other platforms use
/// flutter_web_auth_2 directly.
library;

export 'auth_popup_stub.dart'
    if (dart.library.js_interop) 'auth_popup_web.dart';
