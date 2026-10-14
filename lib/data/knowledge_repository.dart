import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crypto/crypto.dart';

import 'auth_flow.dart';
import 'connection.dart';
import 'connection_store.dart';
import 'content_types.dart';
import 'entry.dart';
import 'liferay_client.dart';
import 'session.dart';

enum SyncState { idle, syncing, online, offline, notConfigured, signedOut }

/// Result of checking one entry against Liferay when its page is opened.
enum EntryCheck { unchanged, updated, deleted, failed }

/// What a synchronization changed in the local copy.
class SyncReport {
  const SyncReport({
    this.created = 0,
    this.updated = 0,
    this.deleted = 0,
    this.initial = false,
  });

  final int created;
  final int updated;
  final int deleted;

  /// True when at least one content type was downloaded from scratch.
  final bool initial;

  bool get hasChanges => created + updated + deleted > 0;

  SyncReport operator +(SyncReport o) => SyncReport(
    created: created + o.created,
    updated: updated + o.updated,
    deleted: deleted + o.deleted,
    initial: initial || o.initial,
  );

  @override
  String toString() => [
    if (created > 0) '$created new',
    if (updated > 0) '$updated updated',
    if (deleted > 0) '$deleted deleted',
  ].join(', ');
}

/// One hit of a Liferay (Search Blueprint) search, linked to the local entry
/// when it is known.
class SearchHit {
  const SearchHit({
    required this.erc,
    required this.title,
    required this.snippet,
    required this.score,
    this.type,
    this.entry,
  });

  final String erc;
  final String title;

  /// Highlighted excerpt; matches are wrapped in `<liferay-hl>` tags.
  final String snippet;
  final double score;
  final ContentType? type;
  final Entry? entry;
}

/// A Search Blueprint targeting the knowledge space.
class Blueprint {
  const Blueprint(this.erc, this.title, this.types);

  factory Blueprint.fromLiferay(Map<String, dynamic> json) {
    final general =
        (json['configuration'] as Map?)?['generalConfiguration'] as Map?;
    return Blueprint(
      json['externalReferenceCode'] as String,
      json['title'] as String? ?? json['externalReferenceCode'] as String,
      {
        for (final c in (general?['searchableAssetTypes'] as List? ?? const []))
          ?contentTypeOfClass('$c'),
      },
    );
  }

  factory Blueprint.fromJson(Map<String, dynamic> j) =>
      Blueprint(j['erc'] as String, j['title'] as String, {
        for (final p in (j['types'] as List).cast<String>())
          ?contentTypesByPath[p],
      });

  final String erc;
  final String title;

  /// Content types the blueprint searches (empty: all).
  final Set<ContentType> types;

  Map<String, dynamic> toJson() => {
    'erc': erc,
    'title': title,
    'types': [for (final t in types) t.restPath],
  };

  /// True when the blueprint's general configuration scopes [spaceErc].
  static bool targets(Map<String, dynamic> json, String spaceErc) {
    final general =
        (json['configuration'] as Map?)?['generalConfiguration'] as Map?;
    final scope = general?['scope'] as List?;
    return scope == null || scope.isEmpty || scope.contains(spaceErc);
  }
}

/// Loads the Northstar knowledge base from Liferay, keeps an offline copy in
/// browser storage, keeps it up to date incrementally and indexes cross
/// references between entries.
class KnowledgeRepository extends ChangeNotifier {
  KnowledgeRepository(this._client);

  final LiferayClient _client;

  /// The offline copy belongs to one owner: what a user (or the service
  /// account of a client) may see depends on their Liferay permissions, so
  /// each owner gets their own storage namespace, never shared.
  ///
  /// Owner key: hash of server + space + identity (user id from the token
  /// `sub` claim, or the client ID for client credentials). Null when nobody
  /// is signed in: nothing is read or written.
  String? get ownerKey {
    final c = connection;
    if (!c.hasCredentials) return null;
    final identity = switch (c.authMode) {
      AuthMode.clientCredentials => 'client:${c.clientId}',
      AuthMode.authorizationCode =>
        _client.session == null ? null : 'user:${_client.session!.userId}',
    };
    if (identity == null) return null;
    final digest = sha256.convert(
      utf8.encode('${c.baseUrl}|${c.spaceErc}|$identity'),
    );
    return digest.toString().substring(0, 20);
  }

  String? get _cachePrefix => ownerKey == null ? null : 'kb.v2.$ownerKey.';
  static const _legacyPrefix = 'kb.v1.';

  /// Source of truth: type rest path -> ERC -> entry JSON.
  final Map<String, Map<String, Map<String, dynamic>>> _raw = {};

  final Map<String, List<Entry>> _byType = {};
  final Map<String, Entry> _byErc = {};
  final Map<String, Entry> _productsByCode = {};
  final Map<String, List<Entry>> _referencedBy = {};

  /// Search Blueprints of the space (cached for offline use).
  List<Blueprint> blueprints = const [];

  /// Blueprint chosen in the search screen (null: Liferay default search).
  String? selectedBlueprintErc;

  Blueprint? get selectedBlueprint =>
      blueprints.where((b) => b.erc == selectedBlueprintErc).firstOrNull;

  SyncState state = SyncState.idle;
  DateTime? syncedAt;
  String? lastError;

  /// Changes brought by the last synchronization (for notifications).
  final lastReport = ValueNotifier<SyncReport?>(null);

  bool get hasData => _byErc.isNotEmpty;
  int get totalCount => _byErc.length;

  List<Entry> entriesOf(ContentType type) => _byType[type.restPath] ?? const [];

  List<Entry> get products => entriesOf(contentTypesByPath['nmgproducts']!);

  Entry? byErc(String erc) => _byErc[erc];

  /// Resolves a reference token: an external reference code or a product code.
  Entry? resolve(String token) => _byErc[token] ?? _productsByCode[token];

  List<Entry> referencedBy(Entry entry) => _referencedBy[entry.erc] ?? const [];

  /// Current Liferay connection (server, space, OAuth 2 client).
  Connection get connection => _client.connection;

  /// The signed-in user (authorization code flow).
  Session? get session => _client.session;

  /// A user must sign in before the app shows any content.
  bool get requiresSignIn =>
      connection.authMode == AuthMode.authorizationCode &&
      _client.session == null;

  /// Applies and saves a new connection, then synchronizes. The user session
  /// survives only if server, space and client are unchanged; the offline
  /// copy of a previous owner is deleted.
  Future<void> reconnect(Connection next, {bool persist = true}) async {
    final previousPrefix = _cachePrefix;
    _client.connect(next, keepSession: connection.sameClient(next));
    if (persist) await ConnectionStore.save(next);
    if (previousPrefix != null && previousPrefix != _cachePrefix) {
      await _removeKeys(previousPrefix);
    }
    await loadCache();
    state = SyncState.idle;
    notifyListeners();
    await sync();
  }

  /// How users sign in; replaced in tests (no browser there).
  @visibleForTesting
  Future<Session> Function(LiferayClient client) signInFlow = AuthFlow.signIn;

  /// Signs the user in (authorization code + PKCE, see [AuthFlow]), then
  /// loads and synchronizes their own offline copy.
  Future<void> signIn() async {
    await signInFlow(_client);
    await signedIn();
  }

  /// Call after a successful sign-in: loads this user's offline copy, then
  /// synchronizes it.
  Future<void> signedIn() async {
    await loadCache();
    state = SyncState.idle;
    await sync();
  }

  /// Signs the user out and deletes their offline copy from this device.
  Future<void> signOut() async {
    final prefix = _cachePrefix;
    if (prefix != null) await _removeKeys(prefix);
    _client.signOut();
    _clearMemory();
    state = SyncState.signedOut;
    notifyListeners();
  }

  Future<void> _removeKeys(String prefix) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith(prefix))) {
      await prefs.remove(key);
    }
  }

  void _clearMemory() {
    _raw.clear();
    blueprints = const [];
    selectedBlueprintErc = null;
    syncedAt = null;
    lastReport.value = null;
    _index();
  }

  /// Restores the current owner's offline copy from local storage (nothing
  /// when nobody is signed in).
  Future<void> loadCache() async {
    _clearMemory();
    await _removeKeys(_legacyPrefix); // pre-v2 cache, shared by everyone
    final prefix = _cachePrefix;
    if (prefix == null) {
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    for (final type in contentTypes) {
      final s = prefs.getString('$prefix${type.restPath}');
      if (s != null) {
        _raw[type.restPath] = {
          for (final j in (jsonDecode(s) as List).cast<Map<String, dynamic>>())
            j['externalReferenceCode'] as String: j,
        };
      }
    }
    final bp = prefs.getString('${prefix}blueprints');
    if (bp != null) {
      blueprints = [
        for (final j in (jsonDecode(bp) as List).cast<Map<String, dynamic>>())
          Blueprint.fromJson(j),
      ];
    }
    final at = prefs.getString('${prefix}syncedAt');
    syncedAt = at == null ? null : DateTime.tryParse(at);
    _index();
    notifyListeners();
  }

  /// Brings the local copy up to date. Content types never downloaded are
  /// fetched in full; the others only fetch entries modified since the last
  /// known modification date, and check by ERC which cached entries were
  /// deleted. On failure the cached copy is kept (offline mode).
  Future<SyncReport?> sync() async {
    if (state == SyncState.syncing) return null;
    if (!connection.hasCredentials) {
      state = SyncState.notConfigured;
      notifyListeners();
      return null;
    }
    if (requiresSignIn) {
      state = SyncState.signedOut;
      notifyListeners();
      return null;
    }
    state = SyncState.syncing;
    lastError = null;
    notifyListeners();
    SyncReport? report;
    try {
      final blueprintsDone = _loadBlueprints(); // never throws
      final reports = await Future.wait(contentTypes.map(_syncType));
      await blueprintsDone;
      report = reports.fold<SyncReport>(const SyncReport(), (a, b) => a + b.$2);
      _index();
      syncedAt = DateTime.now();
      state = SyncState.online;
      await _save({
        for (final r in reports)
          if (r.$1 != null) r.$1!,
      });
      lastReport.value = report;
    } on NotSignedInException catch (e) {
      // Session expired or revoked: hide this user's data until they sign
      // in again (their offline copy stays on the device).
      lastError = '$e';
      _clearMemory();
      state = SyncState.signedOut;
    } catch (e) {
      lastError = '$e';
      state = SyncState.offline;
    }
    notifyListeners();
    return report;
  }

  /// Refreshes the blueprint list; failures (e.g. missing OAuth2 scope) only
  /// disable blueprint selection.
  Future<void> _loadBlueprints() async {
    try {
      final items = await _client.searchBlueprints();
      blueprints = [
        for (final j in items)
          if (Blueprint.targets(j, connection.spaceErc))
            Blueprint.fromLiferay(j),
      ]..sort((a, b) => a.title.compareTo(b.title));
      final prefix = _cachePrefix;
      if (prefix == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '${prefix}blueprints',
        jsonEncode([for (final b in blueprints) b.toJson()]),
      );
    } catch (_) {
      // keep the cached list
    }
  }

  /// Returns the rest path of the type if it changed, and what changed.
  Future<(String?, SyncReport)> _syncType(ContentType type) async {
    final path = type.restPath;
    final cached = _raw[path];
    if (cached == null || cached.isEmpty) {
      // Never synchronized, or empty (no watermark): list everything.
      final items = await _client.fetchAllEntries(path);
      _raw[path] = {
        for (final j in items.map(_slim))
          j['externalReferenceCode'] as String: j,
      };
      final report = SyncReport(created: items.length, initial: cached == null);
      return (cached == null || items.isNotEmpty ? path : null, report);
    }

    // Liferay timestamps have a one second precision: entries modified after
    // the watermark are fetched in full, entries sharing the watermark second
    // are only listed (by ERC) to catch the ones we have never seen.
    final watermark = cached.values
        .map((j) => j['dateModified'] as String? ?? '')
        .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    // Future.wait (not a record's `.wait`, which wraps failures in a
    // ParallelWaitError): a NotSignedInException must reach sync() as is.
    final modifiedF = _client.fetchAllEntries(
      path,
      filter: 'dateModified gt $watermark',
    );
    final sameSecondF = _client.fetchAllEntries(
      path,
      filter: 'dateModified eq $watermark',
      fields: 'externalReferenceCode',
    );
    final existingF = _client.existingErcs(path, cached.keys);
    await Future.wait([modifiedF, sameSecondF, existingF]);
    final modified = await modifiedF;
    final sameSecond = await sameSecondF;
    final existing = await existingF;

    final unseen = sameSecond
        .map((j) => j['externalReferenceCode'] as String)
        .where((erc) => !cached.containsKey(erc))
        .toList();
    final changed = [
      ...modified,
      if (unseen.isNotEmpty)
        ...await _client.fetchAllEntries(
          path,
          filter:
              'externalReferenceCode in '
              '(${unseen.map((e) => "'${e.replaceAll("'", "''")}'").join(',')})',
        ),
    ].map(_slim).toList();

    var created = 0, updated = 0, deleted = 0;
    final changedErcs = {for (final j in changed) j['externalReferenceCode']};
    for (final erc in cached.keys.toList()) {
      if (!existing.contains(erc) && !changedErcs.contains(erc)) {
        cached.remove(erc);
        deleted++;
      }
    }
    for (final j in changed) {
      final erc = j['externalReferenceCode'] as String;
      cached.containsKey(erc) ? updated++ : created++;
      cached[erc] = j;
    }
    final report = SyncReport(
      created: created,
      updated: updated,
      deleted: deleted,
    );
    return (report.hasChanges ? path : null, report);
  }

  /// Checks one entry against Liferay (only its modification date is
  /// requested). Reloads it in full when it changed, removes it when it was
  /// deleted.
  Future<EntryCheck> refreshEntry(String erc) async {
    final entry = _byErc[erc];
    if (entry == null) return EntryCheck.failed;
    final path = entry.type.restPath;
    try {
      final head = await _client.fetchEntry(
        path,
        erc,
        fields: 'externalReferenceCode,dateModified',
      );
      if (head != null && head['dateModified'] == entry.json['dateModified']) {
        return EntryCheck.unchanged;
      }
      final full = head == null ? null : await _client.fetchEntry(path, erc);
      if (full == null) {
        _raw[path]?.remove(erc);
      } else {
        _raw[path]![erc] = _slim(full);
      }
      _index();
      notifyListeners();
      await _save({path});
      return full == null ? EntryCheck.deleted : EntryCheck.updated;
    } catch (_) {
      return EntryCheck.failed; // offline: keep showing the cached copy
    }
  }

  /// Finds an entry by ERC (e.g. a scanned QR code): from the offline copy,
  /// otherwise by asking every content type of the space in parallel.
  Future<Entry?> locate(String erc) async {
    if (_byErc[erc] case final entry?) return entry;
    final found = await Future.wait(
      contentTypes.map((t) async {
        try {
          final json = await _client.fetchEntry(t.restPath, erc);
          return json == null ? null : (t, json);
        } catch (_) {
          return null; // offline
        }
      }),
    );
    final hit = found.nonNulls.firstOrNull;
    if (hit == null) return null;
    final (type, json) = hit;
    (_raw[type.restPath] ??= {})[erc] = _slim(json);
    _index();
    notifyListeners();
    await _save({type.restPath});
    return _byErc[erc];
  }

  /// Drops duplicated plain-text copies to keep the offline cache small.
  Map<String, dynamic> _slim(Map<String, dynamic> json) => {
    for (final e in json.entries)
      if (!e.key.endsWith('RawText') &&
          e.key != 'actions' &&
          e.key != 'friendlyUrlPath_i18n')
        e.key: e.value,
  };

  Future<void> _save(Set<String> paths) async {
    final prefix = _cachePrefix;
    if (prefix == null) return;
    final prefs = await SharedPreferences.getInstance();
    for (final path in paths) {
      await prefs.setString(
        '$prefix$path',
        jsonEncode(_raw[path]?.values.toList() ?? const []),
      );
    }
    if (syncedAt != null) {
      await prefs.setString('${prefix}syncedAt', syncedAt!.toIso8601String());
    }
  }

  void _index() {
    _byType.clear();
    _byErc.clear();
    _productsByCode.clear();
    _referencedBy.clear();
    for (final type in contentTypes) {
      final entries =
          (_raw[type.restPath]?.values ?? const [])
              .map((j) => Entry(type, j))
              .toList()
            ..sort(
              (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            );
      _byType[type.restPath] = entries;
      for (final e in entries) {
        _byErc[e.erc] = e;
        if (type.restPath == 'nmgproducts') {
          final code = e.facetValue('productCode');
          if (code != null) _productsByCode.putIfAbsent(code, () => e);
        }
      }
    }
    for (final entry in _byErc.values) {
      final targets = <Entry>{};
      for (final key in [
        ...entry.type.links.map((l) => l.key),
        ...productCodeFields,
      ]) {
        for (final token in splitCodes(entry.json[key])) {
          final target = resolve(token);
          if (target != null && target != entry) targets.add(target);
        }
      }
      for (final t in targets) {
        (_referencedBy[t.erc] ??= []).add(entry);
      }
    }
  }

  /// Full-text search over the local copy (offline fallback): every term
  /// must match.
  List<Entry> search(String query, {ContentType? type, Blueprint? blueprint}) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final pool = (type == null ? _byErc.values : entriesOf(type)).where(
      (e) =>
          blueprint == null ||
          blueprint.types.isEmpty ||
          blueprint.types.contains(e.type),
    );
    if (terms.isEmpty) return pool.toList();
    final hits = pool.where((e) => terms.every(e.searchText.contains)).toList();
    int score(Entry e) {
      final t = '${e.title} ${e.code}'.toLowerCase();
      return terms.where(t.contains).length;
    }

    hits.sort((a, b) => score(b).compareTo(score(a)));
    return hits;
  }

  /// Searches with Liferay, using the configured Search Blueprint. Hits are
  /// linked to local entries; unknown ones trigger a synchronization.
  Future<List<SearchHit>> searchRemote(
    String query, {
    Blueprint? blueprint,
  }) async {
    final items = await _client.search(query, blueprintErc: blueprint?.erc);
    final hits = [
      for (final item in items)
        if ((item['embedded'] as Map?)?['externalReferenceCode']
            case final String erc)
          SearchHit(
            erc: erc,
            title: item['title'] as String? ?? erc,
            snippet: item['description'] as String? ?? '',
            score: (item['score'] as num?)?.toDouble() ?? 0,
            type:
                _byErc[erc]?.type ??
                contentTypeOfClass(item['entryClassName'] as String? ?? ''),
            entry: _byErc[erc],
          ),
    ];
    if (hits.any((h) => h.entry == null)) unawaited(sync());
    return hits;
  }
}
