// Serves the Flutter web build and proxies Liferay APIs on the same origin.
//
// The Liferay instance does not send CORS headers, so the browser cannot call
// it directly from another origin. Serving the app and `/o/*` from the same
// origin solves this without changing the Liferay configuration.
//
//   dart run tool/serve.dart [--port 8765] [--dir build/web]
//                            [--target https://liferay.example.com]
//
// The default target is read from config/liferay.json (LIFERAY_TARGET).
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  String arg(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final config = File('config/liferay.json').existsSync()
      ? jsonDecode(File('config/liferay.json').readAsStringSync()) as Map
      : const {};
  final target = Uri.parse(arg('target', config['LIFERAY_TARGET'] as String));
  final root = Directory(arg('dir', 'build/web')).absolute;
  final port = int.parse(arg('port', '8765'));

  final client = HttpClient()..autoUncompress = true;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  // Static files get explicit headers; proxied responses keep Liferay's own.
  // (Adding to the defaults would make them accumulate across responses.)
  server.defaultResponseHeaders.clear();
  stdout.writeln('Serving ${root.path} on http://localhost:$port');
  stdout.writeln('Proxying /o/* to $target');

  await for (final request in server) {
    try {
      if (request.uri.path.startsWith('/o/')) {
        await _proxy(client, target, request);
      } else {
        await _static(root, request);
      }
    } catch (e) {
      stderr.writeln('${request.method} ${request.uri}: $e');
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    }
  }
}

const _hopByHop = {
  'connection', 'keep-alive', 'transfer-encoding', 'upgrade', 'host',
  'content-length', 'content-encoding', 'accept-encoding', 'origin', 'referer',
  'cookie',
};

Future<void> _proxy(HttpClient client, Uri target, HttpRequest request) async {
  final uri = target.replace(
      path: request.uri.path, query: request.uri.query.isEmpty ? null : request.uri.query);
  final upstream = await client.openUrl(request.method, uri);
  request.headers.forEach((name, values) {
    if (!_hopByHop.contains(name)) {
      for (final v in values) {
        upstream.headers.add(name, v);
      }
    }
  });
  upstream.headers.set('ngrok-skip-browser-warning', '1');
  upstream.followRedirects = false;
  await upstream.addStream(request);
  final response = await upstream.close();

  final out = request.response..statusCode = response.statusCode;
  response.headers.forEach((name, values) {
    if (!_hopByHop.contains(name) && name != 'set-cookie') {
      for (final v in values) {
        out.headers.add(name, v);
      }
    }
  });
  out.headers.set('cache-control', 'no-store');
  await out.addStream(response);
  await out.close();
  stdout.writeln('${request.method} ${request.uri} -> ${response.statusCode}');
}

const _types = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript',
  'mjs': 'text/javascript',
  'json': 'application/json',
  'wasm': 'application/wasm',
  'png': 'image/png',
  'ico': 'image/x-icon',
  'svg': 'image/svg+xml',
  'otf': 'font/otf',
  'ttf': 'font/ttf',
  'css': 'text/css',
  'webmanifest': 'application/manifest+json',
};

Future<void> _static(Directory root, HttpRequest request) async {
  var path = Uri.decodeComponent(request.uri.path);
  if (path.endsWith('/')) path = '${path}index.html';
  var file = File('${root.path}$path');
  if (!file.absolute.path.startsWith(root.path) || !file.existsSync()) {
    file = File('${root.path}/index.html'); // SPA fallback
  }
  final ext = file.path.split('.').last.toLowerCase();
  final name = file.uri.pathSegments.last;
  final out = request.response
    ..headers.set('content-type', _types[ext] ?? 'application/octet-stream')
    ..headers.set('x-content-type-options', 'nosniff')
    // The service worker owns caching; always revalidate the entry points.
    ..headers.set(
        'cache-control',
        name == 'index.html' || name == 'sw.js' || name == 'flutter_bootstrap.js'
            ? 'no-cache'
            : 'public, max-age=0, must-revalidate');
  await out.addStream(file.openRead());
  await out.close();
}
