import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:northstar_kb/data/connection.dart';
import 'package:northstar_kb/data/knowledge_repository.dart';
import 'package:northstar_kb/data/liferay_client.dart';

Map<String, dynamic> fakeEntry(
  String erc,
  String title, [
  Map<String, dynamic>? extra,
]) => {
  'id': erc.hashCode,
  'externalReferenceCode': erc,
  'title': title,
  'dateModified': '2026-10-13T15:41:47Z',
  'actions': {'get': {}},
  'titleRawText': title,
  'lifecycleStatus': {'key': 'current', 'name': 'Current'},
  ...?extra,
};

/// In-memory Liferay supporting the requests the app makes: OAuth2 token,
/// object entries with `dateModified gt|eq` and `externalReferenceCode in`
/// filters, `fields`, lookup by ERC, search API and blueprints.
class FakeLiferay {
  FakeLiferay() {
    reset();
  }

  late Map<String, Map<String, Map<String, dynamic>>> data;

  /// Authorization codes -> (user id, user name).
  final users = {'code-alice': ('101', 'alice'), 'code-bob': ('102', 'bob')};

  /// Issued user access tokens -> user id.
  final issued = <String, String>{};
  bool revokedRefresh = false;
  int refreshCount = 0;

  /// Lifetime of user access tokens (0: already expired once received).
  int userTokenSeconds = 600;

  Map<String, dynamic> _userTokens((String, String) user) {
    final (id, name) = user;
    String b64(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final token =
        '${b64({'alg': 'none'})}.${b64({'sub': id, 'username': name, 'n': issued.length})}.sig';
    issued[token] = id;
    return {
      'access_token': token,
      'refresh_token': 'rt-$id',
      'expires_in': userTokenSeconds,
    };
  }

  final requests = <String>[];
  bool down = false;
  bool searchForbidden = false;

  void reset() {
    data = {
      'nmgproducts': {
        'PROD-NX400': fakeEntry('PROD-NX400', 'NX-400 Charger', {
          'productCode': 'NX-400',
          'shortDescription': '<p>Dual socket <b>AC</b> charger</p>',
        }),
      },
      'nmgsupportarticles': {
        'KB-NX400-014': fakeEntry(
          'KB-NX400-014',
          'OCPP Connection Failure (E217)',
          {
            'articleId': 'KB-NX400-014',
            'productCode': 'NX-400',
            'relatedArticles': 'KI-NX400-004, UNKNOWN-1',
            'relatedErrorCodes': 'E217',
            'resolution': 'Schedule a nightly reconnect job.',
          },
        ),
      },
      'nmgknownissues': {
        'KI-NX400-004': fakeEntry('KI-NX400-004', 'OCPP session-token leak', {
          'productCode': 'NX-400',
          'relatedSupportArticles': 'KB-NX400-014',
          'severity': {'key': 'high', 'name': 'High'},
        }),
      },
    };
  }

  void put(String type, Map<String, dynamic> entry) =>
      (data[type] ??= {})[entry['externalReferenceCode'] as String] = entry;

  /// Requests to object endpoints that download full entries without filter.
  Iterable<String> get fullDownloads => requests.where(
    (r) =>
        r.contains('/o/c/') &&
        !r.contains('filter=') &&
        !r.contains('fields=') &&
        !r.contains('by-external-reference-code'),
  );

  late final client = MockClient((request) async {
    final url = request.url;
    requests.add('${request.method} $url');
    if (down) throw http.ClientException('network down');
    if (url.path == '/o/oauth2/token') {
      final body = request.bodyFields;
      switch (body['grant_type']) {
        case 'authorization_code':
          final user = users[body['code']];
          if (user == null || body['code_verifier'] == null) {
            return http.Response('{"error":"invalid_grant"}', 400);
          }
          return _json(_userTokens(user));
        case 'refresh_token':
          final user = users.values
              .where((u) => 'rt-${u.$1}' == body['refresh_token'])
              .firstOrNull;
          if (user == null || revokedRefresh) {
            return http.Response('{"error":"invalid_grant"}', 400);
          }
          refreshCount++;
          return _json(_userTokens(user));
        default:
          if (body['client_secret'] != 'secret') {
            return http.Response('{"error":"invalid_client"}', 401);
          }
          return _json({'access_token': 'tok', 'expires_in': 600});
      }
    }
    final bearer = request.headers['Authorization']?.replaceFirst(
      'Bearer ',
      '',
    );
    final caller = bearer == 'tok' ? 'service' : issued[bearer];
    if (caller == null) return http.Response('unauthorized', 401);
    if (url.path == '/o/search/v1.0/search') {
      if (searchForbidden) return http.Response('forbidden', 403);
      final q = url.queryParameters['search']!.toLowerCase();
      final blueprint = url.queryParameters['blueprintExternalReferenceCode'];
      final items = [
        for (final MapEntry(key: type, value: entries) in data.entries)
          if (blueprint != 'BP-SUPPORT' || type == 'nmgsupportarticles')
            for (final e in entries.values)
              if (jsonEncode(e).toLowerCase().contains(q))
                {
                  'title': e['title'],
                  'score': 1.0,
                  'description': 'about <liferay-hl>$q</liferay-hl> here',
                  'entryClassName':
                      'com.liferay.object.model.ObjectDefinition#'
                      '${type == 'nmgsupportarticles' ? 'NMGSUPPORT' : 'NMGOTHER'}',
                  'embedded': {
                    'externalReferenceCode': e['externalReferenceCode'],
                  },
                },
      ];
      return _json({'items': items, 'lastPage': 1, 'totalCount': items.length});
    }
    if (url.path.startsWith('/o/search-experiences-rest/')) {
      if (searchForbidden) return http.Response('forbidden', 403);
      return _json({
        'items': [
          {
            'externalReferenceCode': 'BP-SUPPORT',
            'title': 'Support',
            'configuration': {
              'generalConfiguration': {
                'scope': ['NMG-KNOWLEDGE'],
                'searchableAssetTypes': [
                  'com.liferay.object.model.ObjectDefinition#NMGSUPPORT',
                ],
              },
            },
          },
          {
            'externalReferenceCode': 'BP-OTHER-SPACE',
            'title': 'Other',
            'configuration': {
              'generalConfiguration': {
                'scope': ['OTHER'],
              },
            },
          },
        ],
      });
    }

    // /o/c/{type}/scopes/NMG-KNOWLEDGE[/by-external-reference-code/{erc}]
    final seg = url.pathSegments;
    // Permissions: user 102 ("bob") may not see the known issues.
    final entries = caller == '102' && seg[2] == 'nmgknownissues'
        ? const <String, Map<String, dynamic>>{}
        : data[seg[2]] ?? {};
    if (seg.length == 7 && seg[5] == 'by-external-reference-code') {
      final e = entries[seg[6]];
      if (e == null) return http.Response('{"status":"NOT_FOUND"}', 404);
      return _json(_fields(e, url.queryParameters['fields']));
    }
    var items = entries.values.toList();
    final filter = url.queryParameters['filter'];
    if (filter != null) {
      final date = RegExp(r'^dateModified (gt|eq) (\S+)$').firstMatch(filter);
      final ercs = RegExp(r'^externalReferenceCode in \((.*)\)$')
          .firstMatch(filter);
      if (date != null) {
        items = items.where((e) {
          final c = (e['dateModified'] as String).compareTo(date[2]!);
          return date[1] == 'gt' ? c > 0 : c == 0;
        }).toList();
      } else if (ercs != null) {
        final wanted = ercs[1]!
            .split(',')
            .map((s) => s.replaceAll("'", ''))
            .toSet();
        items = items
            .where((e) => wanted.contains(e['externalReferenceCode']))
            .toList();
      } else {
        throw StateError('unsupported filter $filter');
      }
    }
    final fields = url.queryParameters['fields'];
    return _json({
      'items': [for (final e in items) _fields(e, fields)],
      'lastPage': 1,
      'totalCount': items.length,
    });
  });

  static Map<String, dynamic> _fields(Map<String, dynamic> e, String? fields) =>
      fields == null
      ? e
      : {
          for (final f in fields.split(','))
            if (e.containsKey(f)) f: e[f],
        };

  static http.Response _json(Object body) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

  KnowledgeRepository repository() => KnowledgeRepository(
    LiferayClient(
      httpClient: client,
      resolve: (p) => Uri.parse('https://liferay.test$p'),
      clientId: 'id',
      clientSecret: 'secret',
    ),
  );

  /// A repository for the authorization code flow (public client), whose
  /// sign-in "browser" returns [code].
  KnowledgeRepository userRepository({String code = 'code-alice'}) {
    final repo = KnowledgeRepository(
      LiferayClient(
        httpClient: client,
        connection: Connection(
          liferayUrl: 'https://liferay.test',
          clientId: 'public-client',
        ),
      ),
    );
    repo.signInFlow = (c) => c.signInWithCode(
      code: code,
      codeVerifier: 'verifier',
      redirectUri: 'nmgkb://oauth2',
    );
    return repo;
  }
}
