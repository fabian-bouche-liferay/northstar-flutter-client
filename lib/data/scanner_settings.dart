import 'package:shared_preferences/shared_preferences.dart';

/// Android camera used by the QR scanner.
///
/// On the emulator (see tool/emulator.ps1) the back camera renders the image
/// file written by tool/simulate_scan.dart and the front camera is a PC
/// webcam, so switching camera here switches between both simulations
/// without restarting the emulator.
enum ScanCamera { back, front }

class ScannerSettings {
  ScannerSettings._();

  static const _key = 'settings.scanCamera';

  static ScanCamera camera = ScanCamera.back;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    camera =
        ScanCamera.values.asNameMap()[prefs.getString(_key)] ?? ScanCamera.back;
  }

  static Future<void> setCamera(ScanCamera value) async {
    camera = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
  }
}
