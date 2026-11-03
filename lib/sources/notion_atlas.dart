import 'dart:math';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reading.dart';
import '../services/net.dart';
import '../services/notion_account.dart';
import 'source.dart';

/// Short reads saved in the Reading Atlas (Notion): only rows ticked
/// "Nightly read". The length is checked again on fetch, since pages change.
class NotionAtlasSource extends ReadingSource {
  static const sourceId = 'notion-atlas';
  static const minWords = 300;
  static const maxWords = 4000;

  final NotionAccount account;
  final SharedPreferences? prefs;

  NotionAtlasSource(this.account, [this.prefs]);

  @override
  String get id => sourceId;
  @override
  String get name => 'Reading Atlas (Notion)';
  @override
  String get description {
    final n = account.cachedCount;
    return '${n == null ? 'Rows' : '$n rows'} ticked "Nightly read" in your Sources database '
        '(articles, Wikipedia entries, essays; $minWords–$maxWords words)';
  }

  @override
  ReadingType get type => ReadingType.essay;
  @override
  String get lang => 'auto';
  @override
  bool get builtIn => false;

  /// Pages already found too long, too short or unreadable, so they aren't fetched again.
  Set<String> get _rejected => (prefs?.getStringList('notion:rejected') ?? const []).toSet();

  Future<void> _reject(String url) async {
    final list = [...?prefs?.getStringList('notion:rejected'), url];
    await prefs?.setStringList('notion:rejected', list.length > 3000 ? list.sublist(list.length - 3000) : list);
  }

  @override
  Set<String> get langs => account.cachedLangs;

  @override
  Future<Reading> fetch(Random rng) => fetchFor(type, rng);

  @override
  Future<Reading> fetchFor(ReadingType want, Random rng, {String? lang}) async {
    final rejected = _rejected;
    final pool = (await account.shortSources())
        .where((i) => !rejected.contains(i.url) && !_skipUrl(i.url) && (lang == null || i.lang == lang))
        .toList()
      ..shuffle(rng);
    if (pool.isEmpty) throw SourceException('$name: no unread rows ticked "Nightly read"');

    var tried = 0;
    for (final item in pool.take(6)) {
      tried++;
      final String page;
      try {
        page = await Net.getText(item.url);
      } on RateLimitedException {
        continue;
      } on SourceException {
        await _reject(item.url); // 404, 403 and the like won't fix themselves.
        continue;
      } on Exception {
        continue; // Network trouble: try another, keep this one for later.
      }
      final body = mainText(page);
      final words = body.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      if (words < minWords || words > maxWords) {
        await _reject(item.url);
        continue;
      }
      final meta = html_parser.parse(page).head;
      return Reading(
        type: type,
        title: _title(item, meta),
        author: _author(meta),
        body: body,
        sourceId: id,
        sourceName: item.group == null ? 'Reading Atlas' : 'Reading Atlas · ${item.group}',
        url: item.url,
        lang: detectLang('${item.title} $body'),
      );
    }
    throw SourceException('$name: none of $tried articles tried had $minWords–$maxWords words of readable text');
  }

  /// Files and pages that never hold an article.
  static bool _skipUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return RegExp(r'\.(pdf|epub|docx?|zip|mp3|mp4|jpe?g|png)$').hasMatch(path);
  }

  /// The atlas title is sometimes just the URL; the page's own title is better then.
  static String _title(AtlasItem item, dom.Element? head) {
    final looksLikeUrl = item.title.isEmpty || item.title.contains('/') && !item.title.contains(' ');
    if (!looksLikeUrl || head == null) return item.title;
    final og = head.querySelector('meta[property="og:title"]')?.attributes['content']?.trim();
    final t = og?.isNotEmpty == true ? og! : head.querySelector('title')?.text.trim() ?? '';
    return t.isEmpty ? item.title : t;
  }

  static String? _author(dom.Element? head) {
    final a = head?.querySelector('meta[name="author"]')?.attributes['content']?.trim();
    return a == null || a.isEmpty || a.startsWith('http') ? null : a;
  }
}
