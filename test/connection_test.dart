import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:northstar_kb/app.dart';
import 'package:northstar_kb/data/connection.dart';
import 'package:northstar_kb/data/connection_store.dart';
import 'package:northstar_kb/data/knowledge_repository.dart';
import 'package:northstar_kb/data/liferay_client.dart';
import 'package:northstar_kb/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_liferay.dart';

final _conn = Connection(
  liferayUrl: 'https://liferay.test',
  spaceErc: 'NMG-KNOWLEDGE',
  clientId: 'id',
  clientSecret: 'secret',
  authMode: AuthMode.clientCredentials,
);

void main() {
  late FakeLiferay liferay;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    liferay = FakeLiferay();
  });

  KnowledgeRepository repoWith(Connection c) => KnowledgeRepository(
    LiferayClient(httpClient: liferay.client, connection: c),
  );

  test('connection is stored on the device and survives a restart', () async {
    await ConnectionStore.save(_conn.copyWith(clientId: 'colleague'));
    final loaded = await ConnectionStore.load();
    expect(loaded.clientId, 'colleague');
    expect(loaded.liferayUrl, 'https://liferay.test');
    await ConnectionStore.clear();
    expect(
      (await ConnectionStore.load()).clientId,
      '',
      reason: 'tests run without build defaults',
    );
  });

  test(
    'user sign-in and service account clients are kept separately',
    () async {
      final both = Connection(
        liferayUrl: 'https://liferay.test',
        userClientId: 'public-id',
        serviceClientId: 'service-id',
        serviceClientSecret: 'service-secret',
      );
      expect(both.authMode, AuthMode.authorizationCode);
      expect(both.clientId, 'public-id');
      expect(both.clientSecret, '', reason: 'no secret for user sign-in');

      final service = both.copyWith(authMode: AuthMode.clientCredentials);
      expect(service.clientId, 'service-id');
      expect(service.clientSecret, 'service-secret');
      expect(
        service.copyWith(authMode: AuthMode.authorizationCode).clientId,
        'public-id',
        reason: 'switching mode keeps the other client',
      );

      await ConnectionStore.save(service);
      final loaded = await ConnectionStore.load();
      expect(loaded.userClientId, 'public-id');
      expect(loaded.serviceClientId, 'service-id');
      expect(loaded.serviceClientSecret, 'service-secret');
      expect(loaded.authMode, AuthMode.clientCredentials);
    },
  );

  test('former single-client settings are migrated to the active mode', () {
    final old = Connection.fromJson({
      'liferayUrl': 'https://liferay.test',
      'authMode': 'authorizationCode',
      'clientId': 'public-id',
      'clientSecret': '',
    });
    expect(old.userClientId, 'public-id');
    expect(old.serviceClientId, '');
  });

  test('URL handling: trailing slash, same source', () {
    expect(
      _conn.copyWith(liferayUrl: 'https://liferay.test/').api('/o/x'),
      Uri.parse('https://liferay.test/o/x'),
    );
    expect(_conn.sameSource(_conn.copyWith(clientSecret: 'other')), isTrue);
    expect(
      _conn.sameSource(_conn.copyWith(liferayUrl: 'https://liferay.test/')),
      isTrue,
    );
    expect(_conn.sameSource(_conn.copyWith(spaceErc: 'OTHER')), isFalse);
  });

  test('without credentials the app does not call Liferay', () async {
    final r = repoWith(Connection(liferayUrl: 'https://liferay.test'));
    expect(await r.sync(), isNull);
    expect(r.state, SyncState.notConfigured);
    expect(liferay.requests, isEmpty);
  });

  test(
    'same owner keeps the offline copy; another owner or space: cleared',
    () async {
      final r = repoWith(_conn);
      await r.sync();
      expect(r.totalCount, 3);
      final firstOwner = r.ownerKey!;

      // Same client (e.g. URL written with a trailing slash): same owner.
      liferay.requests.clear();
      await r.reconnect(_conn.copyWith(liferayUrl: 'https://liferay.test/'));
      expect(r.ownerKey, firstOwner);
      expect(
        liferay.fullDownloads.where((q) => q.contains('nmgsupportarticles')),
        isEmpty,
        reason: 'incremental sync, no full download',
      );

      // Another client = another identity (and maybe other permissions): its
      // own cache; the previous owner's copy is deleted from the device.
      await r.reconnect(
        _conn.copyWith(clientId: 'id2', clientSecret: 'secret'),
      );
      expect(r.ownerKey, isNot(firstOwner));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains(firstOwner)), isEmpty);
      expect((await ConnectionStore.load()).clientId, 'id2');

      // Another space: the cache of the previous one is dropped.
      liferay.data = {
        'nmgfaqs': {'FAQ-X': fakeEntry('FAQ-X', 'Other space FAQ')},
      };
      await r.reconnect(_conn.copyWith(spaceErc: 'OTHER-SPACE'));
      expect(r.byErc('KB-NX400-014'), isNull);
      expect(r.byErc('FAQ-X'), isNotNull);
      expect(
        liferay.requests.any((q) => q.contains('/scopes/OTHER-SPACE')),
        isTrue,
      );
    },
  );

  test('connection test reports each step', () async {
    final ok = await testConnection(_conn, httpClient: liferay.client);
    expect(ok.map((c) => c.status), everyElement(CheckStatus.ok));
    expect(ok.map((c) => c.label), [
      'OAuth 2 token',
      'CMS content',
      'Search',
      'Search blueprints',
    ]);

    liferay.searchForbidden = true;
    final noSearch = await testConnection(_conn, httpClient: liferay.client);
    expect(noSearch[2].status, CheckStatus.warning);
    expect(noSearch[2].detail, contains('lacks the scope'));

    final bad = await testConnection(
      _conn.copyWith(clientSecret: 'wrong'),
      httpClient: liferay.client,
    );
    expect(bad.single.status, CheckStatus.error);
    expect(bad.single.detail, contains('client ID and secret'));
  });

  testWidgets('first launch without credentials leads to the settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2400);
    addTearDown(tester.view.reset);
    final r = repoWith(Connection(liferayUrl: 'https://liferay.test'));
    await r.sync();
    await tester.pumpWidget(KnowledgeApp(repository: r));
    await tester.pumpAndSettle();
    // Sign-in gate: nothing but the login page.
    expect(find.text('Sign in with Liferay'), findsOneWidget);
    expect(
      find.text('The Liferay connection is not configured.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Connection settings'));
    await tester.pumpAndSettle();
    expect(find.text('Liferay connection'), findsOneWidget);
    await tester.tap(find.text('Service account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'OAuth 2 client ID'),
      'id',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'OAuth 2 client secret'),
      'secret',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('3 contents'), findsOneWidget);
    expect((await ConnectionStore.load()).clientSecret, 'secret');
  });
}
