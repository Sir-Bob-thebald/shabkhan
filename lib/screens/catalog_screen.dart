import 'package:flutter/material.dart';

import '../models/languages.dart';
import '../models/reading.dart';
import '../services/library.dart';
import '../sources/registry.dart';

/// Every ready-made source, filtered by type and language. Adding one puts
/// it on the Sources tab; nothing here is used until it's added.
class CatalogScreen extends StatefulWidget {
  final Library library;
  final ReadingType? initialType;
  const CatalogScreen({super.key, required this.library, this.initialType});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late ReadingType? _type = widget.initialType;
  String? _lang;

  static String _types(Set<ReadingType> t) =>
      t.length == ReadingType.values.length ? 'Stories, poems & essays' : t.map((x) => x.label).join(', ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Browse sources')),
      body: ListenableBuilder(
        listenable: widget.library,
        builder: (context, _) {
          final lib = widget.library;
          final entries = lib.catalogEntries
              .where((e) => (_type == null || e.source.types.contains(_type)) && (_lang == null || e.lang == _lang))
              .toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final t in [null, ...ReadingType.values])
                      ChoiceChip(
                        label: Text(t == null ? 'All' : t.shortLabel),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ),
                    const SizedBox(width: 8),
                    for (final (code, label) in [
                      (null, 'Any language'),
                      for (final c in {for (final e in lib.catalogEntries) e.lang}) (c, languageOf(c).native),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _lang == code,
                        onSelected: (_) => setState(() => _lang = code),
                      ),
                  ],
                ),
              ),
              for (final e in entries) _EntryTile(library: lib, entry: e, types: _types(e.source.types)),
              if (entries.isEmpty)
                const ListTile(title: Text('Nothing matches these filters')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'Anything with an RSS or Atom feed can be added too: use "Add feed" on the Sources tab.',
                  style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final Library library;
  final CatalogEntry entry;
  final String types;
  const _EntryTile({required this.library, required this.entry, required this.types});

  @override
  Widget build(BuildContext context) {
    final added = library.isAdded(entry);
    return ListTile(
      leading: CircleAvatar(radius: 16, child: Text(entry.lang.toUpperCase(), style: const TextStyle(fontSize: 11))),
      title: Text(entry.source.name),
      subtitle: Text('${entry.source.description}\n$types', maxLines: 3, overflow: TextOverflow.ellipsis),
      isThreeLine: true,
      trailing: added
          ? IconButton(
              tooltip: 'Remove from my sources',
              icon: const Icon(Icons.check_circle),
              onPressed: () => library.removeFromList(entry.source),
            )
          : IconButton.filledTonal(
              tooltip: 'Add',
              icon: const Icon(Icons.add),
              onPressed: () => library.addFromCatalog(entry),
            ),
    );
  }
}
