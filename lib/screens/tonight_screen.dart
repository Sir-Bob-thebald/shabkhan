import 'package:flutter/material.dart';

import '../models/reading.dart';
import '../services/library.dart';
import 'art_widgets.dart';
import 'reader_screen.dart';

class TonightScreen extends StatelessWidget {
  final Library library;
  const TonightScreen({super.key, required this.library});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final night = library.tonight;
        final done = night.finished.length;
        final theme = Theme.of(context);
        return RefreshIndicator(
          onRefresh: library.ensureTonight,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                child: Text(
                  done == 3 ? 'All three read. Sleep well.' : '$done of 3 read tonight',
                  style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              for (final type in ReadingType.values) ...[
                _ReadingCard(library: library, night: night, type: type),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReadingCard extends StatelessWidget {
  final Library library;
  final Night night;
  final ReadingType type;
  const _ReadingCard({required this.library, required this.night, required this.type});

  static const _icons = {
    ReadingType.story: Icons.auto_stories_outlined,
    ReadingType.poem: Icons.format_quote_outlined,
    ReadingType.essay: Icons.lightbulb_outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = night.readings[type];
    final loading = library.loading.contains(type);
    final error = library.errors[type];
    final finished = night.finished.contains(type);

    final header = Row(
      children: [
        Icon(_icons[type], size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(type.label.toUpperCase(),
            style: theme.textTheme.labelMedium!.copyWith(letterSpacing: 1.2, color: theme.colorScheme.primary)),
        if (finished) ...[
          const SizedBox(width: 8),
          Icon(Icons.check_circle, size: 16, color: theme.colorScheme.tertiary),
        ],
        const Spacer(),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          IconButton(
            tooltip: 'Pick another',
            icon: const Icon(Icons.shuffle),
            onPressed: () => library.reroll(type),
          ),
      ],
    );

    Widget content;
    if (reading != null) {
      final excerpt = reading.body.replaceAll(RegExp(r'\s*\n\s*'), reading.type == ReadingType.poem ? ' / ' : ' ');
      content = Directionality(
        textDirection: reading.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(reading.title, style: theme.textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (reading.author != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(reading.author!, style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.secondary)),
              ),
            const SizedBox(height: 8),
            Text(excerpt, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
            Text('${reading.sourceName}‎ · ${reading.minutes} min',
                textDirection: TextDirection.ltr, // mixed English/Persian source names
                style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    } else if (error != null && !loading) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Couldn't fetch a ${type.label.toLowerCase()}.", style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(error, style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error), maxLines: 4),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: () => library.reroll(type), child: const Text('Try again')),
        ],
      );
    } else {
      content = Text('Finding something good…', style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.outline));
    }

    final art = library.artOn ? reading?.art : null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (art != null) Positioned.fill(child: ArtBackdrop(art)),
          _cardBody(context, reading, header, content),
        ],
      ),
    );
  }

  Widget _cardBody(BuildContext context, Reading? reading, Widget header, Widget content) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: reading == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ReaderScreen(library: library, reading: reading, night: night)),
                ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, Padding(padding: const EdgeInsets.only(right: 12), child: content)],
          ),
        ),
      ),
    );
  }
}
