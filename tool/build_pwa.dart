// Builds the WebAssembly PWA and fills the service worker precache list.
//
//   dart run tool/build_pwa.dart                                    # dev build
//   dart run tool/build_pwa.dart --config config/liferay.public.json  # to share
//
// A build made with liferay.public.json embeds no OAuth 2 client: users enter
// their own client ID and secret in the app (Liferay connection settings).
//
// Set FLUTTER to the flutter executable if it is not next to this Dart SDK.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final i = args.indexOf('--config');
  final config = i >= 0 ? args[i + 1] : 'config/liferay.json';
  final flutter = Platform.environment['FLUTTER'] ?? _flutterNextToDart();
  final build = await Process.start(
    flutter,
    [
      'build', 'web',
      '--wasm', // dart2wasm + skwasm, with a JS fallback for older browsers
      '--no-web-resources-cdn', // serve CanvasKit/skwasm ourselves (offline)
      '--release',
      '--dart-define-from-file=$config',
    ],
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  if (await build.exitCode != 0) exit(1);

  final root = Directory('build/web');
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.substring(root.path.length + 1).replaceAll('\\', '/'))
      .where((p) =>
          p != 'sw.js' &&
          p != 'flutter_service_worker.js' &&
          !p.endsWith('.map') &&
          !p.endsWith('.symbols') &&
          !p.startsWith('.'))
      .toList()
    ..sort();

  // FNV-1a over every file: the version changes whenever the build changes,
  // which makes the browser install the new service worker.
  var hash = 0x811c9dc5;
  for (final p in files) {
    for (final b in [...utf8.encode(p), ...File('build/web/$p').readAsBytesSync()]) {
      hash = ((hash ^ b) * 0x01000193) & 0xffffffff;
    }
  }
  final version = hash.toRadixString(16).padLeft(8, '0');
  final assets = ['./', ...files];

  final sw = File('build/web/sw.js');
  sw.writeAsStringSync(sw
      .readAsStringSync()
      .replaceFirst('__BUILD_VERSION__', version)
      .replaceFirst('/*__ASSETS__*/[]', const JsonEncoder.withIndent('  ').convert(assets)));
  final bytes = files.fold<int>(0, (s, p) => s + File('build/web/$p').lengthSync());
  stdout.writeln('PWA ready: version $version, ${assets.length} precached files '
      '(${(bytes / 1024 / 1024).toStringAsFixed(1)} MB)');
}

String _flutterNextToDart() {
  // <flutter>/bin/cache/dart-sdk/bin/dart(.exe) -> <flutter>/bin/flutter(.bat)
  final bin = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  return '${bin.path}${Platform.pathSeparator}flutter${Platform.isWindows ? '.bat' : ''}';
}
