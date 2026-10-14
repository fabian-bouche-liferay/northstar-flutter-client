import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_kb/app.dart';
import 'package:northstar_kb/data/scanner_settings.dart';
import 'package:northstar_kb/screens/scan_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_liferay.dart';

void main() {
  test('ercFromQr accepts raw ERCs and app links', () {
    expect(ercFromQr('KB-NX400-014'), 'KB-NX400-014');
    expect(ercFromQr('  REL-NX400-4.8.1\n'), 'REL-NX400-4.8.1');
    expect(
      ercFromQr('https://kb.example.com/#/entry/KI-NX400-004'),
      'KI-NX400-004',
    );
    expect(ercFromQr('http://localhost:8765/#/entry/PROC%2DX?x=1'), 'PROC-X');
    expect(ercFromQr('hello world'), isNull);
    expect(ercFromQr(''), isNull);
    expect(ercFromQr(null), isNull);
  });

  testWidgets('entry page shows the QR code of its ERC', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 2400);
    addTearDown(tester.view.reset);
    final r = FakeLiferay().repository();
    await r.sync();
    await tester.pumpWidget(KnowledgeApp(repository: r));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support Articles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OCPP Connection Failure (E217)'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('QR code'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.byType(QrImageView)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('KB-NX400-014')),
      findsOneWidget,
    );
  });

  test('locate finds a scanned ERC missing from the offline copy', () async {
    SharedPreferences.setMockInitialValues({});
    final liferay = FakeLiferay();
    final r = liferay.repository();
    await r.sync();
    liferay.put('nmgfaqs', fakeEntry('FAQ-SCANNED', 'Scanned FAQ'));
    final entry = await r.locate('FAQ-SCANNED');
    expect(entry!.type.restPath, 'nmgfaqs');
    expect(r.byErc('FAQ-SCANNED'), entry);
    expect(await r.locate('NOPE-404'), isNull);
  });

  testWidgets('hidden developer settings choose the scanner camera', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await ScannerSettings.load();
    expect(ScannerSettings.camera, ScanCamera.back);
    final r = FakeLiferay().repository();
    await r.sync();
    await tester.pumpWidget(KnowledgeApp(repository: r));
    await tester.pumpAndSettle();

    // flutter_test runs as Android: the scanner (and the menu) are available.
    await tester.longPress(find.text('Northstar Enterprise Knowledge'));
    await tester.pumpAndSettle();
    expect(find.text('Developer settings'), findsOneWidget);
    await tester.tap(find.text('Front camera'));
    await tester.pumpAndSettle();
    expect(ScannerSettings.camera, ScanCamera.front);

    ScannerSettings.camera = ScanCamera.back;
    await ScannerSettings.load(); // persisted
    expect(ScannerSettings.camera, ScanCamera.front);
  });
}
