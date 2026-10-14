// Simulates photographing a content QR code with the Android emulator.
//
// The emulator is started with its back camera rendering an image file:
//   emulator -avd nmg_pixel -camera-back imagefile:<project>/build/camera/feed.png
// This tool composes a "photo" (the QR card of an ERC, slightly rotated, on a
// desk-like background) into that file; the emulator camera then shows it.
//
//   dart run tool/simulate_scan.dart KB-NX400-014
//   dart run tool/simulate_scan.dart --blank      (camera sees no QR code)
//
// QR cards come from `dart run tool/qr_codes.dart` (build/qr/<ERC>.png).
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/simulate_scan.dart <ERC>|--blank');
    exit(64);
  }
  // 4:3 landscape, like the emulated camera sensor.
  final scene = img.Image(width: 1600, height: 1200, numChannels: 3);
  // Desk background: soft vertical gradient.
  for (var y = 0; y < scene.height; y++) {
    final v = 150 + (y * 40 ~/ scene.height);
    img.drawLine(scene,
        x1: 0, y1: y, x2: scene.width - 1, y2: y,
        color: img.ColorRgb8(v, v - 10, v - 25));
  }
  if (args.first != '--blank') {
    final card = File('build/qr/${args.first}.png');
    if (!card.existsSync()) {
      stderr.writeln('${card.path} not found: run tool/qr_codes.dart first');
      exit(66);
    }
    // Alpha channel so the rotated corners stay transparent.
    var qr = img.decodePng(card.readAsBytesSync())!.convert(numChannels: 4);
    qr = img.copyResize(qr, height: 520, interpolation: img.Interpolation.average);
    // The emulated camera shows the full image height but only a band around
    // x = 145..760 (measured with a calibration grid): center the card there.
    const cx = 452, cy = 600;
    final x = cx - qr.width ~/ 2, y = cy - qr.height ~/ 2;
    // Paper shadow, then the slightly tilted card.
    img.fillRect(scene,
        x1: x + 12, y1: y + 12, x2: x + qr.width + 12, y2: y + qr.height + 12,
        color: img.ColorRgb8(110, 100, 90));
    qr = img.copyRotate(qr, angle: 4, interpolation: img.Interpolation.linear);
    img.compositeImage(scene, qr,
        dstX: cx - qr.width ~/ 2, dstY: cy - qr.height ~/ 2);
  }
  final out = File('build/camera/feed.png')..createSync(recursive: true);
  out.writeAsBytesSync(img.encodePng(scene));
  stdout.writeln('Camera now sees ${args.first == '--blank' ? 'no QR code' : args.first}'
      ' (${out.absolute.path})');
}
