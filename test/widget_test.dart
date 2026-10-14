import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_kb/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_liferay.dart';

void main() {
  late FakeLiferay liferay;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    liferay = FakeLiferay();
  });

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    addTearDown(tester.view.reset);
    final r = liferay.repository();
    await r.sync();
    await tester.pumpWidget(KnowledgeApp(repository: r));
    await tester.pumpAndSettle();
  }

  testWidgets('browse: home -> type -> entry -> related product', (
    tester,
  ) async {
    await start(tester);
    expect(find.text('Northstar Enterprise Knowledge'), findsOneWidget);
    expect(find.textContaining('3 contents'), findsOneWidget);

    await tester.tap(find.text('Support Articles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OCPP Connection Failure (E217)'));
    await tester.pumpAndSettle();

    expect(find.text('Resolution'), findsOneWidget);
    expect(find.textContaining('up to date'), findsOneWidget);
    expect(
      find.textContaining('KI-NX400-004 — OCPP session-token leak'),
      findsOneWidget,
    );
    expect(find.text('UNKNOWN-1'), findsOneWidget); // unresolved stays a chip

    await tester.tap(find.text('NX-400').first);
    await tester.pumpAndSettle();
    expect(find.text('NX-400 Charger'), findsOneWidget);
    expect(find.text('Related knowledge (2)'), findsOneWidget);
  });

  testWidgets('opening a content deleted in the CMS', (tester) async {
    await start(tester);
    liferay.data['nmgknownissues']!.clear();
    await tester.tap(find.text('Known Issues'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OCPP session-token leak'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('has been deleted from the CMS'),
      findsOneWidget,
    );
  });

  testWidgets('search with a blueprint shows highlighted Liferay hits', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byType(SearchBar));
    await tester.enterText(find.byType(SearchBar), 'nx-400');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('3 results · Liferay search'), findsOneWidget);

    await tester.tap(find.text('Support'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('1 result · Liferay search · blueprint BP-SUPPORT'),
      findsOneWidget,
    );
    expect(
      find.textContaining('about nx-400 here', findRichText: true),
      findsOneWidget,
    );

    liferay.searchForbidden = true; // e.g. missing OAuth2 scope
    await tester.enterText(find.byType(TextField).first, 'NX-400 charger');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Local search (offline copy) · Support'),
      findsOneWidget,
    );
  });
}
