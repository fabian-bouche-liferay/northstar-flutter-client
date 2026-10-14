import 'package:flutter/material.dart';

import '../app.dart';
import '../data/content_types.dart';
import '../data/entry.dart';
import '../widgets/common.dart';

/// Lists the entries of one content type with text filter and facets.
class TypeScreen extends StatefulWidget {
  const TypeScreen({super.key, required this.type});

  final ContentType type;

  @override
  State<TypeScreen> createState() => _TypeScreenState();
}

class _TypeScreenState extends State<TypeScreen> {
  String _query = '';
  final Map<String, String> _selected = {}; // facet field -> value

  @override
  Widget build(BuildContext context) {
    final repo = RepositoryScope.of(context);
    final type = widget.type;
    final all = repo.search(_query, type: type);
    final entries = all
        .where(
          (e) => _selected.entries.every((f) => e.facetValue(f.key) == f.value),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(type.icon, color: type.color),
            const SizedBox(width: 12),
            Flexible(child: Text(type.label)),
          ],
        ),
      ),
      body: Column(
        children: [
          const SyncStatusBar(),
          Constrained(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.filter_list),
                  hintText: 'Filter ${type.label.toLowerCase()}',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
          ),
          Constrained(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  for (final facet in type.facets) ...[
                    _FacetChip(
                      facet: facet,
                      entries: repo.entriesOf(type),
                      selected: _selected[facet.key],
                      onSelected: (v) => setState(
                        () => v == null
                            ? _selected.remove(facet.key)
                            : _selected[facet.key] = v,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    '${entries.length} result${entries.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('No matching content.'))
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) =>
                        Constrained(child: EntryTile(entry: entries[i])),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FacetChip extends StatelessWidget {
  const _FacetChip({
    required this.facet,
    required this.entries,
    required this.selected,
    required this.onSelected,
  });

  final FieldDef facet;
  final List<Entry> entries;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    // value -> (label, count)
    final values = <String, (String, int)>{};
    for (final e in entries) {
      final v = e.facetValue(facet.key);
      if (v == null) continue;
      final current = values[v];
      values[v] = (e.text(facet.key) ?? v, (current?.$2 ?? 0) + 1);
    }
    if (values.length < 2 && selected == null) return const SizedBox.shrink();
    final sorted = values.entries.toList()
      ..sort((a, b) => a.value.$1.compareTo(b.value.$1));
    final label = selected == null
        ? facet.label
        : '${facet.label}: ${values[selected]?.$1 ?? selected}';

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: () => onSelected(null),
          leadingIcon: Icon(selected == null ? Icons.check : null),
          child: const Text('All'),
        ),
        for (final v in sorted)
          MenuItemButton(
            onPressed: () => onSelected(v.key),
            leadingIcon: Icon(selected == v.key ? Icons.check : null),
            trailingIcon: Text('${v.value.$2}'),
            child: Text(v.value.$1),
          ),
      ],
      builder: (context, controller, _) => FilterChip(
        label: Text(label),
        selected: selected != null,
        onSelected: (_) =>
            controller.isOpen ? controller.close() : controller.open(),
        avatar: selected == null ? const Icon(Icons.arrow_drop_down) : null,
        showCheckmark: true,
      ),
    );
  }
}
