import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../app.dart';
import '../data/content_types.dart';
import '../data/entry.dart';
import '../data/knowledge_repository.dart';
import '../widgets/common.dart';
import '../widgets/qr_dialog.dart';

/// Shows one entry from the offline copy, and checks with Liferay (by its
/// modification date only) whether it was updated or deleted meanwhile.
class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key, required this.erc});

  final String erc;

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  EntryCheck? _check; // null while checking

  String get erc => widget.erc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final check = await RepositoryScope.of(context).refreshEntry(erc);
      if (!mounted) return;
      setState(() => _check = check);
      if (check == EntryCheck.updated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This content was updated in Liferay: reloaded.'),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final entry = repo.byErc(erc);
    if (entry == null) {
      final deleted = _check == EntryCheck.deleted;
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: repo.state == SyncState.syncing
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      deleted ? Icons.delete_outline : Icons.search_off,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      deleted
                          ? 'Content "$erc" has been deleted from the CMS.'
                          : 'Content "$erc" not found.',
                    ),
                    if (deleted)
                      const Text('It was removed from the offline copy.'),
                  ],
                ),
        ),
      );
    }
    final theme = Theme.of(context);
    final sections = entry.type.sections
        .where((s) => (entry.json[s.key] as String?)?.trim().isNotEmpty == true)
        .toList();
    final referencedBy = repo.referencedBy(entry);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(entry.type.icon, color: entry.type.color),
            const SizedBox(width: 12),
            Flexible(child: Text(entry.type.singular)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'QR code',
            icon: const Icon(Icons.qr_code_2),
            onPressed: () => showEntryQr(context, entry),
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.pushNamed(context, Routes.search()),
          ),
        ],
      ),
      body: Column(
        children: [
          const SyncStatusBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: Constrained(
                maxWidth: 860,
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(entry: entry, repo: repo),
                      for (final s in sections) ...[
                        const SizedBox(height: 16),
                        _Section(
                          title: s.label,
                          child: RichField(value: entry.json[s.key] as String),
                        ),
                      ],
                      for (final link in entry.type.links)
                        if (splitCodes(entry.json[link.key]).isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _Section(
                            title: link.label,
                            child: _References(
                              codes: splitCodes(entry.json[link.key]),
                              repo: repo,
                            ),
                          ),
                        ],
                      if (referencedBy.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _Section(
                          title: entry.type.restPath == 'nmgproducts'
                              ? 'Related knowledge (${referencedBy.length})'
                              : 'Referenced by (${referencedBy.length})',
                          padding: EdgeInsets.zero,
                          child: _GroupedEntries(entries: referencedBy),
                        ),
                      ],
                      if (entry.tags.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in entry.tags)
                              ActionChip(
                                avatar: const Icon(Icons.tag, size: 16),
                                label: Text(tag),
                                onPressed: () => Navigator.pushNamed(
                                  context,
                                  Routes.search(tag),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        [
                          'ERC ${entry.erc}',
                          if (entry.dateModified != null)
                            'modified ${formatDate(entry.dateModified!)}',
                          if (entry
                                  .json['systemProperties']?['version']?['number'] !=
                              null)
                            'version ${entry.json['systemProperties']['version']['number']}',
                          switch (_check) {
                            null => 'checking for updates…',
                            EntryCheck.unchanged => 'up to date',
                            EntryCheck.updated => 'reloaded from Liferay',
                            EntryCheck.failed => 'offline copy',
                            EntryCheck.deleted => 'deleted',
                          },
                        ].join('  ·  '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.entry, required this.repo});

  final Entry entry;
  final KnowledgeRepository repo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badges = <Widget>[
      if (entry.lifecycleName != null)
        StatusBadge(
          entry.lifecycleName!,
          color: StatusBadge.lifecycleColor(entry.lifecycleKey),
          icon: Icons.history_toggle_off,
        ),
      if (entry.confidentialityName != null)
        StatusBadge(
          entry.confidentialityName!,
          color: StatusBadge.confidentialityColor(entry.confidentialityKey),
          icon: Icons.lock_outline,
        ),
      if (entry.text('severity') != null)
        StatusBadge(
          'Severity: ${entry.text('severity')}',
          color: StatusBadge.severityColor(entry.facetValue('severity')),
          icon: Icons.priority_high,
        ),
    ];
    final facts = entry.type.facts
        .where((f) => entry.text(f.key) != null && f.key != entry.type.idField)
        .toList();

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TypeAvatar(entry: entry, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.code,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: entry.type.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(entry.title, style: theme.textTheme.headlineSmall),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: badges),
            ],
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 28,
                runSpacing: 12,
                children: [
                  for (final f in facts)
                    _Fact(entry: entry, field: f, repo: repo),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.entry, required this.field, required this.repo});

  final Entry entry;
  final FieldDef field;
  final KnowledgeRepository repo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = entry.text(field.key)!;
    // Product codes become links to the product page.
    final codes = productCodeFields.contains(field.key)
        ? splitCodes(value)
        : const <String>[];
    final linked = codes.where((c) => repo.resolve(c) != null).toList();

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 2),
          if (linked.isEmpty)
            Text(value, style: theme.textTheme.bodyMedium)
          else
            Wrap(
              spacing: 8,
              children: [
                for (final c in codes)
                  InkWell(
                    onTap: repo.resolve(c) == null
                        ? null
                        : () => Navigator.pushNamed(
                            context,
                            Routes.entry(repo.resolve(c)!.erc),
                          ),
                    child: Text(
                      c,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: repo.resolve(c) == null
                            ? null
                            : theme.colorScheme.primary,
                        decoration: repo.resolve(c) == null
                            ? null
                            : TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 20),
  });

  final String title;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Renders a rich text (HTML) or plain text field. Plain text with inline
/// numbered steps ("1. … 2. …") is split into a list.
class RichField extends StatelessWidget {
  const RichField({super.key, required this.value});

  final String value;

  static final _steps = RegExp(r'\s(?=\d{1,2}\.\s)');

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5);
    final v = value.trim();
    if (v.startsWith('<')) {
      return HtmlWidget(
        v,
        textStyle: style,
        customStylesBuilder: (e) =>
            e.localName == 'p' ? {'margin': '0 0 0.7em 0'} : null,
      );
    }
    final parts = RegExp(r'^1\.\s').hasMatch(v) ? v.split(_steps) : [v];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in parts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(p, style: style),
          ),
      ],
    );
  }
}

class _References extends StatelessWidget {
  const _References({required this.codes, required this.repo});

  final List<String> codes;
  final KnowledgeRepository repo;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final c in codes)
        if (repo.resolve(c) case final target?)
          ActionChip(
            avatar: Icon(target.type.icon, size: 18, color: target.type.color),
            label: Text(
              '${target.code} — ${target.title}',
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () =>
                Navigator.pushNamed(context, Routes.entry(target.erc)),
          )
        else
          Chip(label: Text(c)),
    ],
  );
}

class _GroupedEntries extends StatelessWidget {
  const _GroupedEntries({required this.entries});

  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in contentTypes)
          if (entries.any((e) => e.type == type)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                type.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            for (final e in entries.where((e) => e.type == type))
              EntryTile(entry: e),
          ],
        const SizedBox(height: 8),
      ],
    );
  }
}
