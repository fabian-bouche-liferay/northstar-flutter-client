import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:northstar_kb/data/content_types.dart';
import 'package:northstar_kb/data/knowledge_repository.dart';
import 'package:northstar_kb/data/liferay_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_liferay.dart';

void main() {
  late FakeLiferay liferay;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    liferay = FakeLiferay();
  });

  /// A repository restarted from the browser storage written so far.
  Future<KnowledgeRepository> restart() async {
    final r = liferay.repository();
    await r.loadCache();
    liferay.requests.clear();
    return r;
  }

  group('first synchronization', () {
    test('downloads every content type with a single token', () async {
      final r = liferay.repository();
      final report = await r.sync();
      expect(r.state, SyncState.online);
      expect(r.totalCount, 3);
      expect(report!.initial, isTrue);
      expect(liferay.requests.where((c) => c.contains('oauth2')).length, 1);
      expect(liferay.fullDownloads.length, contentTypes.length);
    });

    test('resolves cross references and product codes both ways', () async {
      final r = liferay.repository();
      await r.sync();
      final kb = r.byErc('KB-NX400-014')!;
      final product = r.byErc('PROD-NX400')!;
      expect(r.resolve('NX-400'), product);
      expect(r.resolve('KI-NX400-004')!.title, 'OCPP session-token leak');
      expect(r.resolve('UNKNOWN-1'), isNull);
      expect(
        r.referencedBy(product).map((e) => e.erc),
        unorderedEquals(['KB-NX400-014', 'KI-NX400-004']),
      );
      expect(r.referencedBy(kb).map((e) => e.erc), ['KI-NX400-004']);
    });
  });

  group('incremental synchronization', () {
    setUp(() async => liferay.repository().sync());

    test('nothing changed: no full download, no change reported', () async {
      final r = await restart();
      final report = await r.sync();
      expect(report!.hasChanges, isFalse);
      expect(report.initial, isFalse);
      // Only the types that are empty (no watermark) are listed in full.
      expect(liferay.fullDownloads.length, contentTypes.length - 3);
      expect(
        liferay.fullDownloads.where((r) => r.contains('nmgsupportarticles')),
        isEmpty,
      );
      expect(
        liferay.requests,
        contains(contains('dateModified%20gt%202026-10-13T15%3A41%3A47Z')),
      );
      expect(
        liferay.requests,
        contains(contains('externalReferenceCode%20in')),
      );
    });

    test('picks up modified and created entries after the watermark', () async {
      liferay.data['nmgsupportarticles']!['KB-NX400-014']!
        ..['title'] = 'OCPP failure (E217) — revised'
        ..['dateModified'] = '2026-10-14T09:00:00Z';
      liferay.put(
        'nmgfaqs',
        fakeEntry('FAQ-NEW', 'New FAQ', {
          'dateModified': '2026-10-14T09:00:01Z',
        }),
      );
      final r = await restart();
      final report = await r.sync();
      expect(report.toString(), '1 new, 1 updated');
      expect(r.byErc('KB-NX400-014')!.title, 'OCPP failure (E217) — revised');
      expect(r.byErc('FAQ-NEW'), isNotNull);
      expect(report!.initial, isFalse);
      expect(
        liferay.fullDownloads.where((r) => r.contains('nmgsupportarticles')),
        isEmpty,
        reason: 'modified entries come from the dateModified filter',
      );
    });

    test(
      'catches an entry created in the same second as the watermark',
      () async {
        liferay.put(
          'nmgsupportarticles',
          fakeEntry('KB-SAME-SECOND', 'Same second'),
        );
        final r = await restart();
        final report = await r.sync();
        expect(report!.created, 1);
        expect(r.byErc('KB-SAME-SECOND'), isNotNull);
      },
    );

    test('detects deletions from the cached ERCs', () async {
      liferay.data['nmgknownissues']!.remove('KI-NX400-004');
      final r = await restart();
      final report = await r.sync();
      expect(report!.deleted, 1);
      expect(r.byErc('KI-NX400-004'), isNull);
      expect(r.referencedBy(r.byErc('PROD-NX400')!).map((e) => e.erc), [
        'KB-NX400-014',
      ]);
      // the deletion is persisted
      expect((await restart()).byErc('KI-NX400-004'), isNull);
    });
  });

  group('entry page check', () {
    setUp(() async => liferay.repository().sync());

    test('unchanged: only the modification date is requested', () async {
      final r = await restart();
      expect(await r.refreshEntry('KB-NX400-014'), EntryCheck.unchanged);
      expect(
        liferay.requests.where((q) => q.contains('/o/c/')).single,
        contains(
          'by-external-reference-code/KB-NX400-014?fields=externalReferenceCode%2CdateModified',
        ),
      );
    });

    test('updated: the full entry is reloaded and persisted', () async {
      liferay.data['nmgsupportarticles']!['KB-NX400-014']!
        ..['resolution'] = 'Upgrade to 4.8.1.'
        ..['dateModified'] = '2026-10-14T10:00:00Z';
      final r = await restart();
      expect(await r.refreshEntry('KB-NX400-014'), EntryCheck.updated);
      expect(r.byErc('KB-NX400-014')!.json['resolution'], 'Upgrade to 4.8.1.');
      expect(
        (await restart()).byErc('KB-NX400-014')!.json['resolution'],
        'Upgrade to 4.8.1.',
      );
    });

    test('deleted: 404 removes it from the offline copy', () async {
      liferay.data['nmgsupportarticles']!.clear();
      final r = await restart();
      expect(await r.refreshEntry('KB-NX400-014'), EntryCheck.deleted);
      expect(r.byErc('KB-NX400-014'), isNull);
      expect((await restart()).byErc('KB-NX400-014'), isNull);
    });

    test('offline: the cached copy is kept', () async {
      liferay.down = true;
      final r = await restart();
      expect(await r.refreshEntry('KB-NX400-014'), EntryCheck.failed);
      expect(r.byErc('KB-NX400-014'), isNotNull);
    });
  });

  group('search', () {
    test(
      'local search matches all terms in titles and stripped HTML',
      () async {
        final r = liferay.repository();
        await r.sync();
        expect(r.search('e217').map((e) => e.erc), contains('KB-NX400-014'));
        expect(r.search('nightly reconnect').single.erc, 'KB-NX400-014');
        expect(r.search('dual AC').single.erc, 'PROD-NX400');
        expect(r.search('<b>'), isEmpty);
        expect(
          r.search('nightly', type: contentTypesByPath['nmgknownissues']),
          isEmpty,
        );
      },
    );

    test('blueprints of the space are loaded and cached', () async {
      final r = liferay.repository();
      await r.sync();
      expect(r.blueprints.map((b) => b.erc), ['BP-SUPPORT']);
      expect(r.blueprints.single.types, {
        contentTypesByPath['nmgsupportarticles'],
      });
      final offline = await restart();
      expect(offline.blueprints.single.title, 'Support');
    });

    test('remote search goes through the selected blueprint', () async {
      final r = liferay.repository();
      await r.sync();
      final all = await r.searchRemote('nx-400');
      expect(all.length, 3);
      final support = await r.searchRemote(
        'nx-400',
        blueprint: r.blueprints.single,
      );
      expect(support.single.erc, 'KB-NX400-014');
      expect(support.single.entry, r.byErc('KB-NX400-014'));
      expect(support.single.snippet, contains('<liferay-hl>'));
      expect(
        liferay.requests.last,
        contains('blueprintExternalReferenceCode=BP-SUPPORT'),
      );
    });

    test('offline search applies the blueprint content types', () async {
      final r = liferay.repository();
      await r.sync();
      final bp = r.blueprints.single;
      expect(r.search('NX-400').length, 3);
      expect(r.search('NX-400', blueprint: bp).single.erc, 'KB-NX400-014');
    });

    test('a hit unknown locally triggers a synchronization', () async {
      final r = liferay.repository();
      await r.sync();
      liferay.put(
        'nmgsupportarticles',
        fakeEntry('KB-FRESH', 'Fresh E217 article', {
          'dateModified': '2026-10-15T00:00:00Z',
        }),
      );
      final hits = await r.searchRemote('fresh');
      expect(hits.single.entry, isNull);
      expect(hits.single.type, contentTypesByPath['nmgsupportarticles']);
      await pumpEventQueue();
      expect(r.byErc('KB-FRESH'), isNotNull);
    });
  });

  group('client', () {
    test('expired token (401) is renewed once', () async {
      var tokens = 0;
      var first = true;
      final client = LiferayClient(
        httpClient: MockClient((req) async {
          if (req.url.path == '/o/oauth2/token') {
            tokens++;
            return http.Response(
              jsonEncode({'access_token': 'tok$tokens'}),
              200,
            );
          }
          if (first) {
            first = false;
            return http.Response('expired', 401);
          }
          return http.Response(jsonEncode({'items': [], 'lastPage': 1}), 200);
        }),
        resolve: (p) => Uri.parse('https://liferay.test$p'),
        clientId: 'id',
        clientSecret: 'secret',
      );
      expect(await client.fetchAllEntries('nmgfaqs'), isEmpty);
      expect(tokens, 2);
    });

    test('offline: cache survives a restart and network failures', () async {
      await liferay.repository().sync();
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(
        prefs.getKeys().singleWhere((k) => k.endsWith('.nmgsupportarticles')),
      )!;
      expect(cached, isNot(contains('RawText')));
      expect(cached, isNot(contains('"actions"')));

      liferay.down = true;
      final offline = await restart();
      expect(offline.totalCount, 3);
      await offline.sync();
      expect(offline.state, SyncState.offline);
      expect(offline.lastError, contains('network down'));
      expect(offline.totalCount, 3, reason: 'cached data is kept');
    });
  });
}
