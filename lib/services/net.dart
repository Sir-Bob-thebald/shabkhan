import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// Thrown when a source cannot produce a usable reading this attempt.
class SourceException implements Exception {
  final String message;
  SourceException(this.message);
  @override
  String toString() => message;
}

/// The server asked us to slow down; retrying straight away only makes it worse.
class RateLimitedException extends SourceException {
  RateLimitedException(String host) : super('$host is busy (rate limited); try again later');
}

void _check(http.Response res, String url) {
  final host = Uri.parse(url).host;
  if (res.statusCode == 429) throw RateLimitedException(host);
  if (res.statusCode != 200) throw SourceException('HTTP ${res.statusCode} from $host');
}

class Net {
  static const _timeout = Duration(seconds: 25);

  /// Contact details for the User-Agent, given at build time with
  /// `--dart-define=CONTACT=https://…` (a page or `mailto:` of yours).
  /// Wikimedia asks API clients for one and limits clients without it more
  /// strictly.
  static const contact = String.fromEnvironment('CONTACT');
  static const userAgent =
      'NightlyReader/1.0 (${contact == '' ? 'personal reading app' : '$contact; personal reading app'})';
  static const _headers = {'User-Agent': userAgent};

  static http.Client client = http.Client();

  static Future<String> getText(String url) async {
    final res = await client
        .get(Uri.parse(url), headers: _headers)
        .timeout(_timeout);
    _check(res, url);
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  static Future<dynamic> getJson(String url) async => jsonDecode(await getText(url));

  static Future<dynamic> postJson(String url, Object body) async {
    final res = await client
        .post(
          Uri.parse(url),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    _check(res, url);
    return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
  }
}

/// Converts an HTML fragment into readable plain text with paragraph breaks.
String htmlToText(String html) => elementToText(html_parser.parseFragment(html));

String elementToText(dom.Node root) {
  final buf = StringBuffer();
  const blocks = {
    'p', 'div', 'br', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', //
    'blockquote', 'tr', 'section', 'article', 'pre',
  };

  void walk(dom.Node node, {bool pre = false}) {
    if (node is dom.Text) {
      // Source-code newlines are just whitespace in HTML; only <br>/blocks break lines.
      buf.write(pre ? node.text : node.text.replaceAll(RegExp(r'\s+'), ' '));
      return;
    }
    if (node is! dom.Element && node is! dom.DocumentFragment) return;
    final tag = node is dom.Element ? node.localName : null;
    if (tag == 'script' || tag == 'style' || tag == 'sup') return;
    if (tag == 'br') {
      buf.write('\n');
      return;
    }
    final isBlock = blocks.contains(tag);
    if (isBlock) buf.write('\n\n');
    if (tag == 'li') buf.write('• ');
    for (final child in node.nodes) {
      walk(child, pre: pre || tag == 'pre');
    }
    if (isBlock) buf.write('\n\n');
  }

  walk(root);
  return tidyText(buf.toString());
}

/// Picks the element holding the most paragraph text: a light "reader mode".
/// Articles split into `<section>`s (Wikipedia, for one) are followed in order,
/// keeping the headings of sections that have text.
String mainText(String pageHtml) {
  final doc = html_parser.parse(pageHtml);
  for (final junk in doc.querySelectorAll('script, style, nav, header, footer, aside, form, .comments, #comments')) {
    junk.remove();
  }
  int direct(dom.Element el) =>
      el.children.where((c) => c.localName == 'p').fold<int>(0, (s, p) => s + p.text.length);
  int score(dom.Element el) =>
      direct(el) + el.children.where((c) => c.localName == 'section').fold<int>(0, (s, c) => s + direct(c));
  dom.Element? best;
  var bestLen = 0;
  for (final el in doc.querySelectorAll('article, main, section, div')) {
    final len = score(el);
    if (len > bestLen) {
      best = el;
      bestLen = len;
    }
  }
  if (best == null) return '';
  final out = <String>[];
  String? heading;
  void walk(dom.Element el) {
    for (final c in el.children) {
      final tag = c.localName;
      if (tag == 'p' || tag == 'blockquote') {
        final t = elementToText(c);
        if (t.isEmpty) continue;
        if (heading != null) out.add(heading!);
        heading = null;
        out.add(t);
      } else if (tag == 'section') {
        walk(c);
      } else if (const {'h2', 'h3', 'h4'}.contains(tag)) {
        heading = c.text.trim();
      } else if (c.classes.contains('mw-heading')) {
        heading = c.querySelector('h2, h3, h4')?.text.trim();
      }
    }
  }

  walk(best);
  return out.join('\n\n');
}

/// Normalizes whitespace while keeping paragraph and line breaks.
String tidyText(String s) => s
    .replaceAll('\r', '')
    .replaceAll(' ', ' ')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r' *\n *'), '\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
