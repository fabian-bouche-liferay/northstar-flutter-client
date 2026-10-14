import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../data/content_types.dart';
import '../data/entry.dart';
import '../data/knowledge_repository.dart';
import '../widgets/common.dart';

/// Search across the knowledge base. Online, it uses the Liferay search API
/// with the selected Search Blueprint; offline (or on error) it falls back to
/// the local copy, restricted to the blueprint's content types.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  ContentType? _type;

  int _requestId = 0;
  bool _loading = false;
  List<SearchHit>? _hits; // null: no Liferay results (offline/error)
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    final repo = RepositoryScope.of(context);
    final query = _controller.text.trim();
    final id = ++_requestId;
    if (query.isEmpty) {
      setState(() => _setResult(null, null));
      return;
    }
    setState(() => _loading = true);
    try {
      final hits = await repo.searchRemote(
        query,
        blueprint: repo.selectedBlueprint,
      );
      if (id == _requestId && mounted) {
        setState(() => _setResult(hits, null));
      }
    } catch (e) {
      if (id == _requestId && mounted) {
        setState(() => _setResult(null, '$e'));
      }
    }
  }

  void _setResult(List<SearchHit>? hits, String? error) {
    _hits = hits;
    _remoteError = error;
    _loading = false;
  }

  void _selectBlueprint(String? erc) {
    RepositoryScope.of(context).selectedBlueprintErc = erc;
    setState(() => _type = null);
    _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final query = _controller.text.trim();
    final blueprint = repo.selectedBlueprint;

    // Liferay results when available, local copy otherwise.
    final remote = _hits != null;
    final results = remote
        ? _hits!
        : query.isEmpty
        ? const <SearchHit>[]
        : [
            for (final e in repo.search(query, blueprint: blueprint))
              SearchHit(
                erc: e.erc,
                title: e.title,
                snippet: '',
                score: 0,
                type: e.type,
                entry: e,
              ),
          ];
    final counts = <ContentType, int>{};
    for (final h in results) {
      if (h.type != null) counts[h.type!] = (counts[h.type!] ?? 0) + 1;
    }
    final visible = _type == null
        ? results
        : results.where((h) => h.type == _type).toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: widget.initialQuery.isEmpty,
          decoration: const InputDecoration(
            hintText: 'Search the knowledge base',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: (_) => _runSearch(),
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: Column(
        children: [
          const SyncStatusBar(),
          if (repo.blueprints.isNotEmpty)
            Constrained(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: SegmentedButton<String?>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(
                      value: null,
                      icon: Icon(Icons.travel_explore),
                      label: Text('All'),
                    ),
                    for (final b in repo.blueprints)
                      ButtonSegment(
                        value: b.erc,
                        label: Text(b.title.replaceFirst('Northstar ', '')),
                        tooltip: [for (final t in b.types) t.label].join(', '),
                      ),
                  ],
                  selected: {repo.selectedBlueprintErc},
                  onSelectionChanged: (s) => _selectBlueprint(s.first),
                ),
              ),
            ),
          if (query.isNotEmpty)
            Constrained(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _SourceLabel(
                  remote: remote,
                  blueprint: blueprint,
                  error: _remoteError,
                  count: results.length,
                ),
              ),
            ),
          if (counts.length > 1)
            Constrained(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('All types (${results.length})'),
                      selected: _type == null,
                      onSelected: (_) => setState(() => _type = null),
                    ),
                    for (final t in contentTypes)
                      if (counts[t] != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            avatar: Icon(t.icon, size: 16, color: t.color),
                            label: Text('${t.label} (${counts[t]})'),
                            selected: _type == t,
                            onSelected: (_) => setState(() => _type = t),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: query.isEmpty
                ? const Center(
                    child: Text('Type a keyword, e.g. E217 or OCPP.'),
                  )
                : visible.isEmpty
                ? Center(
                    child: Text(
                      _loading ? 'Searching…' : 'No result for "$query".',
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, i) =>
                        Constrained(child: _HitTile(hit: visible[i])),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SourceLabel extends StatelessWidget {
  const _SourceLabel({
    required this.remote,
    required this.blueprint,
    required this.error,
    required this.count,
  });

  final bool remote;
  final Blueprint? blueprint;
  final String? error;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = remote
        ? 'Liferay search${blueprint == null ? '' : ' · blueprint ${blueprint!.erc}'}'
        : 'Local search (offline copy)'
              '${blueprint == null ? '' : ' · ${blueprint!.title} content types'}';
    return Tooltip(
      message: error ?? '',
      child: Row(
        children: [
          Icon(
            remote ? Icons.cloud_done_outlined : Icons.cloud_off,
            size: 16,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$count result${count == 1 ? '' : 's'} · $text',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final entry = hit.entry;
    if (entry != null && hit.snippet.isEmpty) {
      return EntryTile(entry: entry, showType: true);
    }
    final theme = Theme.of(context);
    final type = hit.type;
    return ListTile(
      leading: entry != null
          ? TypeAvatar(entry: entry)
          : Icon(type?.icon ?? Icons.article_outlined, color: type?.color),
      title: Text(hit.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              type?.singular,
              entry?.code ?? hit.erc,
            ].whereType<String>().join('  ·  '),
            style: theme.textTheme.bodySmall,
          ),
          if (hit.snippet.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                highlightedSnippet(hit.snippet, theme),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          if (entry == null)
            Text(
              'Not in the offline copy yet, synchronizing…',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
      isThreeLine: true,
      onTap: entry == null
          ? null
          : () => Navigator.pushNamed(context, Routes.entry(entry.erc)),
    );
  }
}

/// Turns a Liferay snippet (`… <liferay-hl>E217</liferay-hl> …`) into a
/// text span with the matches in bold.
TextSpan highlightedSnippet(String snippet, ThemeData theme) {
  final spans = <TextSpan>[];
  final parts = snippet.split(RegExp(r'</?liferay-hl>'));
  for (var i = 0; i < parts.length; i++) {
    final text = stripHtml(parts[i], trim: false);
    if (text.isEmpty) continue;
    spans.add(
      TextSpan(
        text: text,
        style:
            i
                .isOdd // odd parts are between <liferay-hl> tags
            ? TextStyle(
                fontWeight: FontWeight.w700,
                backgroundColor: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.6,
                ),
              )
            : null,
      ),
    );
  }
  return TextSpan(children: spans);
}
