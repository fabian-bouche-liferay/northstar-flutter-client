import 'package:flutter/material.dart';

import '../data/scanner_settings.dart';

/// Hidden developer settings (long-press the home title on mobile): chooses
/// which camera the QR scanner uses, i.e. which emulator simulation.
Future<void> showDeveloperSettings(BuildContext context) =>
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => const _DeveloperSettings(),
    );

class _DeveloperSettings extends StatefulWidget {
  const _DeveloperSettings();

  @override
  State<_DeveloperSettings> createState() => _DeveloperSettingsState();
}

class _DeveloperSettingsState extends State<_DeveloperSettings> {
  ScanCamera _camera = ScannerSettings.camera;

  Future<void> _select(ScanCamera? value) async {
    if (value == null) return;
    setState(() => _camera = value);
    await ScannerSettings.setCamera(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Developer settings',
                style: theme.textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'QR scanner camera',
                style: theme.textTheme.titleSmall,
              ),
            ),
            RadioGroup<ScanCamera>(
              groupValue: _camera,
              onChanged: _select,
              child: const Column(
                children: [
                  RadioListTile(
                    value: ScanCamera.back,
                    secondary: Icon(Icons.image_outlined),
                    title: Text('Back camera'),
                    subtitle: Text(
                      'Emulator: simulated photo '
                      '(dart run tool/simulate_scan.dart <ERC>)',
                    ),
                  ),
                  RadioListTile(
                    value: ScanCamera.front,
                    secondary: Icon(Icons.videocam_outlined),
                    title: Text('Front camera'),
                    subtitle: Text(
                      'Emulator: PC webcam '
                      '(tool/emulator.ps1 -Webcam webcam1)',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Applies the next time the scanner opens. On a real phone, '
                'keep the back camera.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
