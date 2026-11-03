import 'dart:math';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/reading.dart';
import '../services/net.dart';
import 'source.dart';

/// Public-domain English poems from PoetryDB.
class PoetryDbSource extends ReadingSource {
  @override
  String get id => 'poetrydb';
  @override
  String get name => 'PoetryDB';
  @override
  String get description => 'Public-domain English poems (Dickinson, Keats, Shakespeare…)';
  @override
  ReadingType get type => ReadingType.poem;
  @override
  String get lang => 'en';

  @override
  Future<Reading> fetch(Random rng) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final poems = (await Net.getJson('https://poetrydb.org/random/10') as List).cast<Map>();
      final fitting = poems.where((p) {
        final n = int.tryParse('${p['linecount']}') ?? 0;
        return n >= 4 && n <= 60;
      }).toList();
      if (fitting.isEmpty) continue;
      final p = pick(fitting, rng);
      final title = p['title'] as String;
      final author = p['author'] as String;
      return Reading(
        type: type,
        title: title,
        author: author,
        body: tidyText((p['lines'] as List).join('\n')),
        sourceId: id,
        sourceName: name,
        // Title and author: many poems share a title ("Sonnet", "Song").
        url: 'https://poetrydb.org/title,author/${Uri.encodeComponent(title)};${Uri.encodeComponent(author)}',
        lang: lang,
      );
    }
    throw SourceException('PoetryDB returned no poem of a bedtime length');
  }
}

/// Short stories (or, with another [category], poems) from English Wikisource.
class WikisourceStorySource extends ReadingSource {
  @override
  final String id;
  @override
  final String name;
  @override
  final String description;
  @override
  final ReadingType type;
  final String category;
  final int minChars;

  /// The Wikisource edition: en, de, fr…
  final String wiki;

  WikisourceStorySource({
    this.id = 'wikisource-stories',
    this.name = 'Wikisource',
    this.description = 'Classic English short stories (Kipling, Benson, Chekhov in translation…)',
    this.type = ReadingType.story,
    this.category = 'Short_stories',
    this.minChars = 1500,
    this.wiki = 'en',
  });

  String get _api => 'https://$wiki.wikisource.org/w/api.php';
  static const _skipPrefixes = [
    'Category:', 'Author:', 'Portal:', 'Wikisource:', 'Help:', //
    'Special:', 'Template:', 'File:', 'Page:', 'Index:', 'Talk:',
    // German and French namespaces
    'Kategorie:', 'Autor:', 'Seite:', 'Spezial:', 'Datei:', 'Hilfe:', 'Vorlage:', 'Diskussion:',
    'Catégorie:', 'Auteur:', 'Livre:', 'Portail:', 'Spécial:', 'Fichier:', 'Aide:', 'Modèle:', 'Discussion:',
  ];

  @override
  String get lang => wiki;

  @override
  Future<Reading> fetch(Random rng) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      // Jump to a random spot in the alphabetical listing for a cheap random pick.
      final letter = String.fromCharCode(65 + rng.nextInt(26));
      final list = await Net.getJson('$_api?action=query&format=json&list=categorymembers'
          '&cmtitle=Category:$category&cmtype=page&cmlimit=40'
          '&cmstartsortkeyprefix=$letter') as Map;
      final members = ((list['query'] as Map)['categorymembers'] as List).cast<Map>();
      if (members.isEmpty) continue;
      final title = pick(members, rng)['title'] as String;
      try {
        return await _load(title);
      } on RateLimitedException {
        rethrow;
      } on SourceException {
        continue;
      }
    }
    throw SourceException('Wikisource: no complete story found');
  }

  Future<Reading> _load(String title, {int depth = 0, String? knownAuthor}) async {
    final res = await Net.getJson('$_api?action=parse&format=json&formatversion=2'
        '&redirects=1&prop=text&disablelimitreport=1&page=${Uri.encodeComponent(title)}') as Map;
    final parse = res['parse'] as Map?;
    if (parse == null) throw SourceException('Wikisource: missing page');
    final doc = html_parser.parseFragment(parse['text'] as String);
    final found = doc.querySelector('.contributor-text .fn, #header_author_text')
        ?.text.replaceFirst(RegExp(r'^\s*by\s+', caseSensitive: false), '').trim();
    final author = found != null && found.isNotEmpty ? found : knownAuthor;

    for (final junk in doc.querySelectorAll('table, .ws-noexport, .noprint, .wst-header, .authority-control, '
        '#headertemplate, .licenseContainer, .mw-editsection, .pagenum, .ws-pagenum, '
        '.reference, .references, .mw-references-wrap, style, script')) {
      junk.remove();
    }
    final paragraphs = doc.querySelectorAll('p').map((p) => elementToText(p)).where((t) => t.isNotEmpty);
    final body = paragraphs.join('\n\n');

    if (body.length < minChars) {
      // Probably a "versions of this work" page; follow the first edition link.
      if (depth > 0) throw SourceException('Wikisource: page too short');
      final next = _firstWorkLink(html_parser.parseFragment(parse['text'] as String));
      if (next == null) throw SourceException('Wikisource: no text');
      return _load(next, depth: depth + 1, knownAuthor: author);
    }
    if (body.length > 45000) throw SourceException('Wikisource: too long for one night');

    final pageTitle = parse['title'] as String;
    return Reading(
      type: type,
      title: pageTitle.split('/').last,
      author: author,
      // Printed page numbers ([63]) that some editions keep in the text.
      body: tidyText(body.replaceAll(RegExp(r'\[\d{1,4}\]\s*'), '')),
      sourceId: id,
      sourceName: name,
      url: 'https://$wiki.wikisource.org/wiki/${Uri.encodeComponent(pageTitle.replaceAll(' ', '_'))}',
      lang: lang,
    );
  }

  String? _firstWorkLink(dom.DocumentFragment doc) {
    for (final a in doc.querySelectorAll('a[href^="/wiki/"]')) {
      final target = Uri.decodeComponent(a.attributes['href']!.substring(6).split('#').first);
      if (_skipPrefixes.any(target.startsWith)) continue;
      return target.replaceAll('_', ' ');
    }
    return null;
  }
}

/// Highly rated essays from LessWrong.
class LessWrongSource extends ReadingSource {
  @override
  String get id => 'lesswrong';
  @override
  String get name => 'LessWrong';
  @override
  String get description => 'Top-rated essays on thinking, science and life (≤ 20 min reads)';
  @override
  ReadingType get type => ReadingType.essay;
  @override
  String get lang => 'en';

  @override
  Future<Reading> fetch(Random rng) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final offset = rng.nextInt(1500);
      final res = await Net.postJson('https://www.lesswrong.com/graphql', {
        'query': '{ posts(input: {terms: {view: "top", limit: 10, offset: $offset}}) '
            '{ results { title pageUrl wordCount htmlBody user { displayName } } } }',
      }) as Map;
      final posts = (((res['data'] as Map)['posts'] as Map)['results'] as List).cast<Map>();
      final fitting = posts.where((p) {
        final w = p['wordCount'] as int? ?? 0;
        return w >= 500 && w <= 4000 && p['htmlBody'] != null;
      }).toList();
      if (fitting.isEmpty) continue;
      final p = pick(fitting, rng);
      return Reading(
        type: type,
        title: p['title'] as String,
        author: (p['user'] as Map?)?['displayName'] as String?,
        body: htmlToText(p['htmlBody'] as String),
        sourceId: id,
        sourceName: name,
        url: p['pageUrl'] as String,
        lang: lang,
      );
    }
    throw SourceException('LessWrong: no essay of a suitable length');
  }
}

/// Paul Graham's essays, scraped from his index page.
class PaulGrahamSource extends ReadingSource {
  static const _base = 'https://paulgraham.com';
  static List<String>? _cachedLinks;

  @override
  String get id => 'paulgraham';
  @override
  String get name => 'Paul Graham';
  @override
  String get description => 'Essays on work, startups, writing and how to think';
  @override
  ReadingType get type => ReadingType.essay;
  @override
  String get lang => 'en';

  @override
  Future<Reading> fetch(Random rng) async {
    final links = _cachedLinks ??= await _loadIndex();
    for (var attempt = 0; attempt < 3; attempt++) {
      final page = pick(links, rng);
      final doc = html_parser.parse(await Net.getText('$_base/$page'));
      // The essay is the largest <font> block on the page.
      dom.Element? best;
      for (final f in doc.querySelectorAll('font')) {
        if (best == null || f.text.length > best.text.length) best = f;
      }
      if (best == null) continue;
      final body = elementToText(best);
      if (body.length < 1500 || body.length > 60000) continue;
      return Reading(
        type: type,
        title: doc.querySelector('title')?.text.trim() ?? page,
        author: 'Paul Graham',
        body: body,
        sourceId: id,
        sourceName: name,
        url: '$_base/$page',
        lang: lang,
      );
    }
    throw SourceException('Paul Graham: could not read an essay');
  }

  Future<List<String>> _loadIndex() async {
    final html = await Net.getText('$_base/articles.html');
    final links = RegExp(r'href="([a-z0-9]+\.html)"')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .where((l) => !{'index.html', 'articles.html', 'rss.html'}.contains(l))
        .toSet()
        .toList();
    if (links.isEmpty) throw SourceException('Paul Graham: empty index');
    return links;
  }
}
