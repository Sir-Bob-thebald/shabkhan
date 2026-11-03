import 'package:flutter/material.dart';

import '../models/reading.dart';
import '../services/library.dart';
import 'reader_screen.dart';

/// Past nights, newest first.
class HistoryScreen extends StatelessWidget {
  final Library library;
  const HistoryScreen({super.key, required this.library});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final nights = library.history().where((n) => n.date != library.tonight.date).toList();
        if (nights.isEmpty) {
          return const _Empty(icon: Icons.nights_stay_outlined, text: 'Past nights will appear here.');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: nights.length,
          itemBuilder: (context, i) {
            final n = nights[i];
            return ExpansionTile(
              title: Text(_prettyDate(n.date)),
              subtitle: Text('${n.finished.length} of ${n.readings.length} read'),
              children: [
                for (final r in ReadingType.values.map((t) => n.readings[t]).whereType<Reading>())
                  ReadingTile(library: library, reading: r, night: n),
              ],
            );
          },
        );
      },
    );
  }

  static String _prettyDate(String iso) {
    final d = DateTime.parse(iso);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

/// Bookmarked readings.
class SavedScreen extends StatelessWidget {
  final Library library;
  const SavedScreen({super.key, required this.library});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        if (library.favorites.isEmpty) {
          return const _Empty(icon: Icons.bookmark_outline, text: 'Tap the bookmark while reading to keep a piece here.');
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [for (final r in library.favorites) ReadingTile(library: library, reading: r)],
        );
      },
    );
  }
}

class ReadingTile extends StatelessWidget {
  final Library library;
  final Reading reading;
  final Night? night;
  const ReadingTile({super.key, required this.library, required this.reading, this.night});

  @override
  Widget build(BuildContext context) {
    final done = night?.finished.contains(reading.type) ?? false;
    return ListTile(
      leading: Icon(done ? Icons.check_circle : Icons.circle_outlined,
          color: done ? Theme.of(context).colorScheme.tertiary : null),
      title: Text(reading.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          textDirection: reading.isRtl ? TextDirection.rtl : TextDirection.ltr),
      subtitle: Text('${reading.type.label} · ${reading.author ?? reading.sourceName}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReaderScreen(library: library, reading: reading, night: night)),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: color)),
        ]),
      ),
    );
  }
}
