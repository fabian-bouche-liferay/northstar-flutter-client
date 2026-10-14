import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app.dart';
import '../data/scanner_settings.dart';

/// Extracts a content ERC from a scanned QR code: either the raw ERC
/// (`KB-NX400-014`) or a link to the app (`…/#/entry/KB-NX400-014`).
String? ercFromQr(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final match = RegExp(r'/entry/([^/?#\s]+)').firstMatch(value);
  if (match != null) return Uri.decodeComponent(match[1]!);
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{1,99}$').hasMatch(value)
      ? value
      : null;
}

/// Scans a QR code holding a content ERC, with the camera or from a picture,
/// and opens the content.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    // Chosen in the hidden developer settings (emulator simulations).
    facing: ScannerSettings.camera == ScanCamera.front
        ? CameraFacing.front
        : CameraFacing.back,
  );
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handle(String? raw) async {
    if (_busy) return;
    final erc = ercFromQr(raw);
    if (erc == null) {
      setState(() => _message = 'Not a Northstar content code: "$raw"');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Looking up $erc…';
    });
    final entry = await RepositoryScope.of(context).locate(erc);
    if (!mounted) return;
    if (entry == null) {
      setState(() {
        _busy = false;
        _message = 'Content $erc not found.';
      });
      return;
    }
    await Navigator.pushReplacementNamed(context, Routes.entry(entry.erc));
  }

  /// Simulates "taking a picture" of a QR code: decodes an image from the
  /// gallery with the same ML Kit pipeline as the live camera.
  Future<void> _scanImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final capture = await _controller.analyzeImage(file.path);
    final codes = capture?.barcodes ?? const [];
    if (codes.isEmpty) {
      setState(() => _message = 'No QR code found in this picture.');
      return;
    }
    await _handle(codes.first.rawValue);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan a content QR code'),
        bottom: ScannerSettings.camera == ScanCamera.front
            ? const PreferredSize(
                preferredSize: Size.fromHeight(20),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('Front camera (developer setting)'),
                ),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: _controller.toggleTorch,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) =>
                _handle(capture.barcodes.firstOrNull?.rawValue),
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable: ${error.errorCode.name}.\n'
                  '${ScannerSettings.camera == ScanCamera.front ? _noFrontCamera : ''}'
                  'You can also use "Scan a picture".',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          // Viewfinder
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_message != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.inverseSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: theme.colorScheme.onInverseSurface,
                      ),
                    ),
                  ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _scanImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Scan a picture'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _noFrontCamera =
    'No front camera: on the emulator, start it with tool/emulator.ps1 '
    '(front camera = PC webcam), or pick the back camera in the developer '
    'settings (long-press the home title).\n';
