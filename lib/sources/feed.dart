import 'dart:math';

import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../models/languages.dart';
import '../models/reading.dart';
import '../services/net.dart';
import 'classify.dart';
import 'source.dart';

/// An RSS or Atom feed. Picks a random entry; if the feed only carries a
/// teaser, the linked page is fetched and its main text extracted.
///
/// With no fixed type, each entry is sorted by its content (see [classify]),
/// so one magazine feed can supply stories, poems and essays; [only] limits
/// that to the types it really carries (reviews and interviews are then skipped).
class FeedSource extends ReadingSource {
  static const maxWords = 8000;

  @override
  final String id;
  @override
  final String name;
  final ReadingType? fixedType;
  final String url;
  final String? blurb;
  final Set<ReadingType>? only;

  /// The language of its entries; null until known (learned from the first reading).
  final String? language;

  /// A web page without a feed: its article links are read instead.
  final bool site;

  FeedSource({
    required this.id,
    required this.name,
    required ReadingType? type,
    required this.url,
    this.blurb,
    this.only,
    this.language,
    this.site = false,
  }) : fixedType = type;

  FeedSource copyWith({ReadingType? Function()? type, String? language}) => FeedSource(
        id: id,
        name: name,
        type: type == null ? fixedType : type(),
        url: url,
        blurb: blurb,
        only: only,
        language: language ?? this.language,
        site: site,
      );

  @override
  ReadingType get type => fixedType ?? ReadingType.essay;
  @override
  Set<ReadingType> get types => fixedType == null ? only ?? ReadingType.values.toSet() : {fixedType!};

  @override
  String get description => blurb ?? Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;
  @override
  String get lang => language ?? 'auto';
  @override
  bool get builtIn => false;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'type': fixedType?.name ?? 'auto', 'url': url, 'lang': ?language, if (site) 'site': true};

  factory FeedSource.fromJson(Map<String, dynamic> j) => FeedSource(
        id: j['id'] as String,
        name: j['name'] as String,
        type: j['type'] == 'auto' ? null : ReadingType.values.byName(j['type'] as String),
        url: j['url'] as String,
        language: j['lang'] as String?,
        site: j['site'] as bool? ?? false,
      );

  /// Fetches the feed once, to validate a URL before saving. Returns its title
  /// and language: the feed's own `<language>` tag, or detected from its entries.
  static Future<({String title, String lang})> probe(String url) async {
    final feed = _parse(await Net.getText(url));
    if (feed.items.isEmpty) throw SourceException('The feed has no entries');
    final sample = feed.items.take(5).map((i) => '${i.title} ${htmlToText(i.html)}').join(' ');
    return (title: feed.title, lang: feed.lang ?? detectLang(sample));
  }

  static const _feedPaths = ['/feed', '/rss', '/feed.xml', '/rss.xml', '/atom.xml', '/index.xml', '/feeds/posts/default'];

  /// Works out a source from any link: a feed, a page that names its feed,
  /// a site with a feed at a usual address, or else the page itself, whose
  /// article links are then read ([site] is true).
  static Future<({String url, String title, String lang, bool site})> discover(String input) async {
    final start = Uri.parse(input);
    final page = await Net.getText(input);
    try {
      // The link may be a feed itself; read it from the page already fetched.
      final feed = _parse(page);
      if (feed.items.isNotEmpty) {
        final sample = feed.items.take(5).map((i) => '${i.title} ${htmlToText(i.html)}').join(' ');
        return (url: input, title: feed.title, lang: feed.lang ?? detectLang(sample), site: false);
      }
    } on SourceException {
      // Not a feed.
    }
    final doc = html_parser.parse(page);
    final candidates = <String>[
      for (final l in doc.querySelectorAll('link[rel=alternate]'))
        if (RegExp('rss|atom', caseSensitive: false).hasMatch(l.attributes['type'] ?? '') && l.attributes['href'] != null)
          start.resolve(l.attributes['href']!).toString(),
      for (final p in _feedPaths) start.replace(path: p, query: '').toString().replaceFirst(RegExp(r'\?$'), ''),
    ];
    for (final c in {...candidates}) {
      try {
        final p = await probe(c);
        return (url: c, title: p.title, lang: p.lang, site: false);
      } on Exception {
        continue;
      }
    }
    if (_articleLinks(page, start).length < 3) {
      throw SourceException('No feed found, and the page has too few article links to read from');
    }
    final title = doc.querySelector('meta[property="og:site_name"]')?.attributes['content']?.trim() ??
        doc.querySelector('title')?.text.trim() ??
        start.host;
    final lang = normalizeLang(doc.documentElement?.attributes['lang']) ?? detectLang(htmlToText(page));
    return (url: input, title: title.isEmpty ? start.host : title, lang: lang, site: true);
  }

  static final _notArticle = RegExp(
      r'/(tags?|category|categories|author|authors|login|signin|signup|register|about|contact|privacy|terms|search|'
      r'subscribe|account|cart|shop|page/\d+|wp-admin|feed)(/|$)|\.(jpe?g|png|gif|pdf|mp3|mp4|zip)$',
      caseSensitive: false);

  /// Links on [page] that look like articles on the same site.
  static List<({String url, String text})> _articleLinks(String page, Uri base) {
    final seen = <String>{};
    final out = <({String url, String text})>[];
    for (final a in html_parser.parse(page).querySelectorAll('a[href]')) {
      final Uri u;
      try {
        u = base.resolve(a.attributes['href']!).removeFragment();
      } on FormatException {
        continue;
      }
      if (u.host != base.host || !u.isScheme('https') && !u.isScheme('http')) continue;
      final segs = u.pathSegments.where((p) => p.isNotEmpty).toList();
      if (segs.isEmpty || u.path == base.path || _notArticle.hasMatch(u.path)) continue;
      final last = segs.last;
      if (!(last.contains('-') || last.length >= 12 || RegExp(r'\d{3,}').hasMatch(last))) continue;
      if (seen.add(u.toString())) out.add((url: u.toString(), text: a.text.trim()));
    }
    return out;
  }

  @override
  Future<Reading> fetch(Random rng) => fetchFor(type, rng);

  @override
  Future<Reading> fetchFor(ReadingType want, Random rng, {String? lang}) async {
    final List<_Item> items;
    if (site) {
      items = [
        for (final l in _articleLinks(await Net.getText(url), Uri.parse(url)))
          _Item(title: l.text.length > 8 ? l.text : '', link: l.url, html: ''),
      ];
    } else {
      items = _parse(await Net.getText(url)).items;
    }
    if (items.isEmpty) throw SourceException(site ? '$name: no article links found' : '$name: feed is empty');
    final shuffled = [...items]..shuffle(rng);
    final auto = fixedType == null;
    var tried = 0;
    for (final item in shuffled) {
      if (tried >= (auto ? 6 : 3)) break;
      // Entries whose own categories say they're something else aren't fetched.
      if (auto && item.hint != null && item.hint != want) continue;
      tried++;
      var body = htmlToText(item.html);
      var title = item.title;
      if (body.length < 600 && item.link != null) {
        try {
          final page = await Net.getText(item.link!);
          body = mainText(page);
          if (title.isEmpty) {
            final head = html_parser.parse(page).head;
            title = head?.querySelector('meta[property="og:title"]')?.attributes['content']?.trim() ??
                head?.querySelector('title')?.text.trim() ??
                '';
          }
        } on Exception {
          // Keep the teaser if the page can't be fetched.
        }
      }
      // Video pages, podcast blurbs and transcripts aren't a night's read.
      final words = body.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      if (words < (want == ReadingType.poem ? 20 : 300) || words > maxWords) continue;
      if (auto && classify(title: title, tags: item.tags, text: body) != want) continue;
      return Reading(
        type: want,
        title: title.isEmpty ? name : title,
        author: item.author,
        body: body,
        sourceId: id,
        sourceName: name,
        // Entries without a link still need a key of their own.
        url: item.link ?? '$url#${item.title.hashCode}',
        lang: detectLang('$title $body'),
      );
    }
    throw SourceException(auto
        ? '$name: no ${want.label.toLowerCase()} among the latest entries'
        : '$name: entries had no readable text');
  }

  static _Feed _parse(String xmlText) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlText);
    } on XmlException {
      throw SourceException('Not a valid RSS/Atom feed');
    }
    String? text(XmlElement e, List<String> names) {
      for (final n in names) {
        final found = e.findElements(n).firstOrNull;
        if (found != null && found.innerText.trim().isNotEmpty) return found.innerText.trim();
      }
      return null;
    }

    final items = <_Item>[];
    // RSS 2.0
    for (final it in doc.findAllElements('item')) {
      items.add(_Item(
        title: text(it, ['title']) ?? '',
        link: text(it, ['link']),
        html: text(it, ['content:encoded', 'description']) ?? '',
        author: text(it, ['dc:creator', 'author']),
        tags: [for (final c in it.findElements('category')) c.innerText.trim()],
      ));
    }
    // Atom
    for (final e in doc.findAllElements('entry')) {
      final link = e.findElements('link').where((l) => (l.getAttribute('rel') ?? 'alternate') == 'alternate').firstOrNull;
      items.add(_Item(
        title: text(e, ['title']) ?? '',
        link: link?.getAttribute('href'),
        html: text(e, ['content', 'summary']) ?? '',
        author: e.findElements('author').firstOrNull?.findElements('name').firstOrNull?.innerText.trim(),
        tags: [for (final c in e.findElements('category')) c.getAttribute('term') ?? c.innerText.trim()],
      ));
    }
    final channel = doc.findAllElements('channel').firstOrNull ?? doc.rootElement;
    final declared = text(channel, ['language', 'dc:language']) ?? doc.rootElement.getAttribute('xml:lang');
    // Only codes the app knows; others (or 3-letter ones) are detected instead.
    final lang = normalizeLang(declared);
    return _Feed(text(channel, ['title']) ?? 'Feed', items, languages.containsKey(lang) ? lang : null);
  }
}

class _Feed {
  final String title;
  final List<_Item> items;
  final String? lang;
  _Feed(this.title, this.items, this.lang);
}

class _Item {
  final String title;
  final String? link;
  final String html;
  final String? author;
  final List<String> tags;
  _Item({required this.title, this.link, required this.html, this.author, this.tags = const []});

  /// The type the entry's categories announce (poem or story), if any.
  ReadingType? get hint {
    if (tags.isEmpty) return null;
    final t = classify(tags: tags, text: '');
    return t == ReadingType.essay ? null : t;
  }
}
