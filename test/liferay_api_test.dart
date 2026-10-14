// Integration tests against the real Liferay server, OAuth 2 client
// credentials grant. Configuration comes from config/liferay.json.
//
//   flutter test test/liferay_api_test.dart
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:northstar_kb/data/content_types.dart';
import 'package:northstar_kb/data/entry.dart';
import 'package:northstar_kb/data/liferay_client.dart';

void main() {
  final config = jsonDecode(
    File('config/liferay.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final target = config['LIFERAY_TARGET'] as String;
  final space = config['SPACE_ERC'] as String;

  LiferayClient client({String? secret}) => LiferayClient(
    resolve: (p) => Uri.parse('$target$p'),
    clientId: config['OAUTH_CLIENT_ID'] as String,
    clientSecret: secret ?? config['OAUTH_CLIENT_SECRET'] as String,
  );

  test(
    'client credentials grant returns a bearer token with object scopes',
    () async {
      final response = await http.post(
        Uri.parse('$target/o/oauth2/token'),
        headers: {'ngrok-skip-browser-warning': '1'},
        body: {
          'grant_type': 'client_credentials',
          'client_id': config['OAUTH_CLIENT_ID'],
          'client_secret': config['OAUTH_CLIENT_SECRET'],
        },
      );
      expect(response.statusCode, 200);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      expect(json['token_type'], 'Bearer');
      expect(json['expires_in'], greaterThan(0));
      final scopes = (json['scope'] as String).split(' ').toSet();
      expect(
        scopes,
        containsAll([
          for (final o in [
            'product',
            'supportarticle',
            'knownissue',
            'faq',
            'procedure',
            'techspec',
            'releasenote',
            'policy',
            'corporatearticle',
            'customercase',
            'salesplaybook',
          ])
            'c_nmg$o.everything.read',
        ]),
      );
    },
  );

  test('wrong client secret is rejected', () async {
    await expectLater(
      client(secret: 'secret-wrong').accessToken(),
      throwsA(
        isA<LiferayException>().having(
          (e) => e.statusCode,
          'statusCode',
          anyOf(400, 401),
        ),
      ),
    );
  });

  test('unscoped object endpoint requires the space scope (409)', () async {
    final c = client();
    await expectLater(
      c.getJson('/o/c/nmgfaqs/'),
      throwsA(
        isA<LiferayException>().having((e) => e.statusCode, 'statusCode', 409),
      ),
    );
  });

  test('token is cached between calls', () async {
    final c = client();
    final t1 = await c.accessToken();
    final t2 = await c.accessToken();
    expect(t2, t1);
  });

  group('space $space', () {
    final c = client();
    final all = <String, List<Map<String, dynamic>>>{};

    setUpAll(() async {
      for (final type in contentTypes) {
        all[type.restPath] = await c.fetchAllEntries(type.restPath);
      }
    });

    for (final type in contentTypes) {
      test('${type.label}: entries readable and well formed', () {
        final items = all[type.restPath]!;
        expect(items, isNotEmpty);
        for (final item in items) {
          expect(item['externalReferenceCode'], isNotEmpty);
          expect(item['title'], isA<String>());
          expect(
            item['systemProperties']['scope']['externalReferenceCode'],
            space,
          );
          expect(
            item.containsKey('actions'),
            isFalse,
            reason: 'restrictFields=actions should strip actions',
          );
          // Every field the UI displays exists in the object definition.
          for (final f in [...type.facts, ...type.sections, ...type.links]) {
            expect(
              item.containsKey(f.key),
              isTrue,
              reason: '${type.restPath}.${f.key} is not returned by the API',
            );
          }
        }
      });
    }

    test('incremental sync filters on dateModified', () async {
      final items = all['nmgsupportarticles']!;
      final watermark = items
          .map((e) => e['dateModified'] as String)
          .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
      expect(
        await c.fetchAllEntries(
          'nmgsupportarticles',
          filter: 'dateModified gt $watermark',
        ),
        isEmpty,
      );
      final sameSecond = await c.fetchAllEntries(
        'nmgsupportarticles',
        filter: 'dateModified eq $watermark',
        fields: 'externalReferenceCode',
      );
      expect(sameSecond, isNotEmpty);
      expect(sameSecond.first.keys, ['externalReferenceCode']);
    });

    test('deletion check by ERC batches returns only existing ERCs', () async {
      final ercs = [
        for (final e in all['nmgprocedures']!)
          e['externalReferenceCode'] as String,
      ];
      final existing = await c.existingErcs('nmgprocedures', [
        ...ercs,
        'PROC-DOES-NOT-EXIST',
      ], batchSize: 10);
      expect(existing, ercs.toSet());
    });

    test('entry check by ERC: date only, 404 when missing', () async {
      final head = await c.fetchEntry(
        'nmgsupportarticles',
        'KB-NX400-014',
        fields: 'externalReferenceCode,dateModified',
      );
      expect(
        head!.keys,
        unorderedEquals(['externalReferenceCode', 'dateModified']),
      );
      expect(
        await c.fetchEntry('nmgsupportarticles', 'KB-DOES-NOT-EXIST'),
        isNull,
      );
    });

    test('search blueprints of the space are readable', () async {
      final blueprints = await c.searchBlueprints();
      final ercs = blueprints.map((b) => b['externalReferenceCode']).toList();
      expect(
        ercs,
        containsAll([
          'NMG-BLUEPRINT-SUPPORT-OPERATIONS',
          'NMG-BLUEPRINT-PRODUCT-ENGINEERING',
          'NMG-BLUEPRINT-SALES-CUSTOMER',
          'NMG-BLUEPRINT-CORPORATE-POLICY',
        ]),
      );
    });

    test('search through a blueprint returns ERCs and highlights', () async {
      final hits = await c.search(
        'E217',
        blueprintErc: 'NMG-BLUEPRINT-SUPPORT-OPERATIONS',
      );
      expect(hits, isNotEmpty);
      final ercs = [
        for (final h in hits) h['embedded']['externalReferenceCode'],
      ];
      expect(ercs, contains('KB-NX400-014'));
      expect(
        ercs.every((e) => '$e'.startsWith('KB-') || '$e'.startsWith('FAQ-')),
        isTrue,
        reason: 'support blueprint: support articles and FAQs only',
      );
      expect(hits.first['description'], contains('<liferay-hl>'));
    });

    test('pagination returns every entry', () async {
      final paged = await c.fetchAllEntries('nmgsupportarticles', pageSize: 7);
      expect(paged.length, all['nmgsupportarticles']!.length);
      expect(paged.map((e) => e['id']).toSet().length, paged.length);
    });

    test('most cross references resolve to an existing entry', () {
      final ercs = {
        for (final items in all.values)
          for (final i in items) i['externalReferenceCode'] as String,
      };
      final productCodes = {
        for (final p in all['nmgproducts']!) p['productCode'] as String,
      };
      var total = 0, resolved = 0;
      for (final type in contentTypes) {
        for (final item in all[type.restPath]!) {
          for (final link in type.links) {
            for (final code in splitCodes(item[link.key])) {
              total++;
              if (ercs.contains(code) || productCodes.contains(code)) {
                resolved++;
              }
            }
          }
        }
      }
      // ignore: avoid_print
      print('cross references resolved: $resolved / $total');
      expect(resolved / total, greaterThan(0.8));
    });
  });
}
