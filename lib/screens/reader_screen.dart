import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/languages.dart';
import '../models/reading.dart';
import '../services/library.dart';
import 'art_widgets.dart';

class ReaderScreen extends StatefulWidget {
  final Library library;
  final Reading reading;

  /// The night this reading belongs to, so it can be marked as finished.
  final Night? night;

  const ReaderScreen({super.key, required this.library, required this.reading, this.night});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  Library get library => widget.library;
  Reading get reading => widget.reading;
  Night? get night => widget.night;

  /// The translation being shown, and its language; null shows the original.
  ({String title, String body})? _translated;
  String? _translatedTo;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    final auto = library.autoTranslate(reading.sourceId);
    if (auto != null && auto != reading.lang) _translate(auto);
  }

  Future<void> _translate(String to) async {
    setState(() => _translating = true);
    try {
      final t = await library.translate(reading, to);
      if (mounted) {
        setState(() {
          _translated = t;
          _translatedTo = to;
        });
      }
    } on Exception catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not translate: $e')));
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  void _toggleTranslation() {
    if (_translated != null) {
      return setState(() {
        _translated = null;
        _translatedTo = null;
      });
    }
    final to = library.translateTo != reading.lang ? library.translateTo : (reading.lang == 'en' ? 'fa' : 'en');
    _translate(to);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final theme = Theme.of(context);
        final r = reading;
        // The picture may arrive after the reader opened.
        final latest = night?.readings[r.type];
        final art = library.artOn ? (latest?.key == r.key ? latest!.art : r.art) : null;
        final shownLang = _translatedTo ?? r.lang;
        final rtl = isRtlLang(shownLang);
        final title = _translated?.title ?? r.title;
        final body = _translated?.body ?? r.body;
        final isPoem = r.type == ReadingType.poem;
        final finished = night?.finished.contains(r.type) ?? false;
        final bodyStyle = theme.textTheme.bodyLarge!.copyWith(
          fontSize: 18 * library.textScale,
          height: rtl ? 2.0 : 1.65,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(r.type.label),
            actions: [
              IconButton(
                tooltip: 'Smaller text',
                icon: const Icon(Icons.text_decrease),
                onPressed: library.textScale > Library.minTextScale
                    ? () => library.setTextScale(library.textScale - 0.1)
                    : null,
              ),
              IconButton(
                tooltip: 'Larger text',
                icon: const Icon(Icons.text_increase),
                onPressed: library.textScale < Library.maxTextScale
                    ? () => library.setTextScale(library.textScale + 0.1)
                    : null,
              ),
              IconButton(
                tooltip: _translated != null ? 'Show the original' : 'Translate into ${languageOf(library.translateTo).name}',
                icon: _translating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_translated != null ? Icons.g_translate : Icons.translate),
                onPressed: _translating ? null : _toggleTranslation,
              ),
              IconButton(
                tooltip: library.isFavorite(r) ? 'Remove from saved' : 'Save',
                icon: Icon(library.isFavorite(r) ? Icons.bookmark : Icons.bookmark_outline),
                onPressed: () => library.toggleFavorite(r),
              ),
              IconButton(
                tooltip: 'Open original',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication),
              ),
            ],
          ),
          body: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: SelectionArea(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, art == null ? 16 : 0, 24, 48),
                children: [
                  if (art != null)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                        child: ArtHeader(library: library, art: art),
                      ),
                    ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: isPoem ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            textAlign: isPoem ? TextAlign.center : TextAlign.start,
                            style: theme.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (r.author != null) ...[
                            const SizedBox(height: 6),
                            Text(r.author!, style: theme.textTheme.titleMedium!.copyWith(color: theme.colorScheme.primary)),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            '${r.sourceName}‎ · ${r.minutes} min',
                            textDirection: TextDirection.ltr, // mixed English/Persian source names
                            style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline),
                          ),
                          if (_translatedTo != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Machine-translated from ${languageOf(r.lang).name} into ${languageOf(_translatedTo!).name}',
                              textDirection: TextDirection.ltr,
                              style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.tertiary),
                            ),
                          ],
                          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider()),
                          Text(body, style: bodyStyle, textAlign: isPoem ? TextAlign.center : TextAlign.start),
                          const SizedBox(height: 32),
                          if (night != null)
                            Center(
                              child: finished
                                  ? OutlinedButton.icon(
                                      onPressed: () => library.setFinished(night!, r.type, false),
                                      icon: const Icon(Icons.check_circle),
                                      label: const Text('Finished'),
                                    )
                                  : FilledButton.icon(
                                      onPressed: () {
                                        library.setFinished(night!, r.type, true);
                                        Navigator.pop(context);
                                      },
                                      icon: const Icon(Icons.check),
                                      label: const Text('Mark as read'),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
