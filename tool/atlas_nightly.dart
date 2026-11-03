// Decides which Reading Atlas sources work as a nightly read and records it
// in Notion, as a "Nightly read" checkbox and a "Words" number on each row.
// Pages are measured with the app's own text extractor, so what is ticked
// here is what the app can show.
//
//   dart run tool/atlas_nightly.dart scan     # fetch and measure pages (resumable)
//   dart run tool/atlas_nightly.dart report   # print the verdicts, nothing is written
//   dart run tool/atlas_nightly.dart push     # write the verdicts to Notion
//   dart run tool/atlas_nightly.dart check    # compare the live database with the app's expectations
//
// Needs NOTION_TOKEN in the environment, or reads it from ../../notion/.env.
// Notion blocks Iranian IPs. If the VPN only runs as a proxy, point at it,
// e.g. for Geph in PowerShell: $env:HTTPS_PROXY = "127.0.0.1:9910"
// Results are kept in tool/atlas_scan.json.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:nightly_reader/services/net.dart';

/// The atlas's Sources database (its ID or link), from the environment so it
/// isn't in the source code: `ATLAS_DB=… dart run tool/atlas_nightly.dart scan`.
final sourcesDb = () {
  final m = RegExp(r'[0-9a-fA-F]{32}').firstMatch((Platform.environment['ATLAS_DB'] ?? '').replaceAll('-', ''));
  if (m == null) {
    stderr.writeln('Set ATLAS_DB to the Sources database ID or link.');
    exit(64);
  }
  return m.group(0)!.toLowerCase();
}();
const scanFile = 'tool/atlas_scan.json';

/// Types that can hold a readable text. Searches, videos, audio, courses,
/// tools, AI chats and opportunities never can.
const readableTypes = {'Essay / article', 'Encyclopedia', 'Book / text', 'Scholarship', 'Post', 'Discussion'};

const minWords = 300, maxWords = 4000;

/// Sites whose pages are listings, profiles, shops, games or tools, not prose.
/// Chosen by reviewing the first scan.
const blockedHosts = <String>[
  'boursieplus.ir', 'bookkand.com', 'jangal.com', 'minervabookstore.com', 'iranketab.ir', // ads and shops
  'hamyarnb.com', 'bimlearn.org', 'jobvision.ir', 'herfeh-honarmand.com', // how-tos and jobs
  'prnewswire.com', 'sciencespo.fr', 'sorbonne-universite.fr', 'accaglobal.com', // notices and admissions
  'khavarianarchitects.com', 'forum.obsidian.md', 'dzone.com', 'nexusmods.com', 'notion.so',
  'course.fast.ai', 'researchmap.jp', 'researchgate.net', 'philpeople.org',
  'uesp.net', // game wiki lore
];

/// Single pages that are calls, landing pages or site home pages.
const blockedUrls = <String>[
  'https://digitaldante.columbia.edu/the-dante-course',
  'https://lacaninscotland.com',
  'https://www.unqualified-reservations.org',
  'https://tripleampersand.org/support-the-iranian-revolution-2026',
];

/// Titles that mark pages without a continuous text.
final blockedTitle = RegExp(
    r'^(List of|Lists of|Index of|Category:|Template:|Portal:|Search:|فهرست)|\(disambiguation\)|Outline of',
    caseSensitive: false);

/// The verdict for one scanned row: null when usable, otherwise the reason.
String? rejectReason(Map e) {
  if (e['err'] != null) return 'unreachable (${e['err']})';
  final host = Uri.parse(e['url'] as String).host.replaceFirst('www.', '');
  if (blockedHosts.any((h) => host == h || host.endsWith('.$h'))) return 'not prose ($host)';
  final bare = (e['url'] as String).replaceFirst(RegExp(r'/$'), '');
  if (blockedUrls.contains(bare) || Uri.parse(bare).path.isEmpty) return 'landing page';
  if (blockedTitle.hasMatch(e['title'] as String)) return 'list or index page';
  final words = e['words'] as int, paras = e['paras'] as int;
  if (words < minWords) return 'too short ($words words)';
  if (words > maxWords) return 'too long ($words words)';
  // Headings count as paragraphs, so prose with many sections still averages ~20+.
  if (words / paras < 20) return 'not prose (fragments, ${(words / paras).round()} words per paragraph)';
  return null;
}

// ───────────────────────────── Notion ─────────────────────────────

late final String token;

Future<Map<String, dynamic>> notion(String method, String path, [Object? body]) async {
  final uri = Uri.https('api.notion.com', '/v1/$path');
  final headers = {'Authorization': 'Bearer $token', 'Notion-Version': '2022-06-28', 'Content-Type': 'application/json'};
  Object? last;
  for (var attempt = 0; attempt < 8; attempt++) {
    if (attempt > 0) await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
    final http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (method != 'GET') req.body = jsonEncode(body ?? {});
      res = await http.Response.fromStream(await Net.client.send(req).timeout(const Duration(seconds: 40)));
    } on Exception catch (e) {
      last = e; // This network drops many TLS handshakes; just try again.
      continue;
    }
    if (res.statusCode == 429 || res.statusCode >= 500) {
      last = 'HTTP ${res.statusCode}';
      continue;
    }
    final text = utf8.decode(res.bodyBytes);
    if (!text.trimLeft().startsWith('{')) {
      print('Notion answered HTTP ${res.statusCode} with a web page, not the API.');
      if (res.statusCode == 403) print('That is Cloudflare blocking this IP (Notion refuses Iranian IPs). Turn on a VPN.');
      exit(2);
    }
    final data = jsonDecode(text) as Map<String, dynamic>;
    if (res.statusCode != 200) throw Exception('$method $path → ${res.statusCode}: ${data['message']}');
    return data;
  }
  throw Exception('$method $path kept failing: $last');
}

String plain(Map props, String name) {
  final p = props[name] as Map?;
  return [for (final t in (p?[p['type']] as List? ?? const []).cast<Map>()) t['plain_text'] ?? ''].join().trim();
}

String? select(Map props, String name) => ((props[name] as Map?)?['select'] as Map?)?['name'] as String?;

Future<List<Map<String, dynamic>>> allRows() async {
  final rows = <Map<String, dynamic>>[];
  String? cursor;
  do {
    final data = await notion('POST', 'databases/$sourcesDb/query', {'page_size': 100, 'start_cursor': ?cursor});
    for (final page in (data['results'] as List).cast<Map>()) {
      final props = page['properties'] as Map;
      rows.add({
        'id': page['id'],
        'url': (props['URL'] as Map?)?['url'],
        'title': plain(props, 'Name'),
        'type': select(props, 'Type'),
        'status': select(props, 'Status'),
        'origin': select(props, 'Origin'),
        'group': plain(props, 'Chrome group'),
        'nightly': (props['Nightly read'] as Map?)?['checkbox'],
        'wordsProp': (props['Words'] as Map?)?['number'],
      });
    }
    cursor = data['has_more'] == true ? data['next_cursor'] as String? : null;
    stdout.write('\r${rows.length} rows');
  } while (cursor != null);
  print('');
  return rows;
}

// ───────────────────────────── commands ─────────────────────────────

Map<String, dynamic> loadScan() =>
    File(scanFile).existsSync() ? (jsonDecode(File(scanFile).readAsStringSync()) as Map).cast() : {};

void saveScan(Map scan) => File(scanFile).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(scan));

Future<void> scan() async {
  final rows = await allRows();
  final data = loadScan();
  final todo = rows.where((r) {
    final url = r['url'] as String?;
    if (url == null || !readableTypes.contains(r['type'])) return false;
    final prev = data[url] as Map?;
    return prev == null || prev['err'] != null && prev['err'] != 'HTTP 404' && prev['err'] != 'HTTP 410';
  }).toList();
  print('${todo.length} pages to measure (${data.length} already done)');
  var done = 0;
  Future<void> worker(Iterator<Map<String, dynamic>> it) async {
    while (true) {
      final Map<String, dynamic> r;
      // The iterator is shared; Dart is single-threaded, so this is safe.
      if (!it.moveNext()) return;
      r = it.current;
      final url = r['url'] as String;
      final entry = {...r, 'err': null, 'words': 0, 'paras': 0, 'pushed': (data[url] as Map?)?['pushed']};
      if (RegExp(r'\.(pdf|epub|docx?|zip|mp3|mp4|jpe?g|png)$').hasMatch(Uri.parse(url).path.toLowerCase())) {
        entry['err'] = 'file, not a page';
      } else {
        try {
          final text = mainText(await Net.getText(url));
          final paras = text.split('\n\n').where((p) => p.trim().isNotEmpty).toList();
          entry['words'] = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          entry['paras'] = paras.length;
          entry['lang'] = detectLangSimple(text);
        } on SourceException catch (e) {
          entry['err'] = '$e'.replaceFirst(RegExp(r' from .*'), '');
        } on Exception catch (e) {
          entry['err'] = e is TimeoutException ? 'timeout' : 'network';
        }
      }
      data[url] = entry;
      if (++done % 25 == 0) {
        saveScan(data);
        stdout.write('\r$done / ${todo.length}');
      }
    }
  }

  final it = todo.iterator;
  await Future.wait([for (var i = 0; i < 10; i++) worker(it)]);
  saveScan(data);
  print('\rmeasured $done pages');
}

String detectLangSimple(String text) => RegExp(r'[؀-ۿ]').allMatches(text).length > text.length / 4 ? 'fa' : 'en';

void report({bool verbose = false}) {
  final data = loadScan();
  final reasons = <String, int>{};
  final good = <Map>[];
  for (final e in data.values.cast<Map>()) {
    final why = rejectReason(e);
    if (why == null) {
      good.add(e);
    } else {
      final k = why.replaceAll(RegExp(r' \(.*'), '');
      reasons[k] = (reasons[k] ?? 0) + 1;
    }
  }
  print('${data.length} measured, ${good.length} usable');
  reasons.forEach((k, v) => print('  rejected, $k: $v'));
  final byType = <String, int>{};
  for (final e in good) {
    byType[e['type'] as String] = (byType[e['type']] ?? 0) + 1;
  }
  print('usable by type: $byType');
  if (verbose) {
    good.sort((a, b) => Uri.parse(a['url']).host.compareTo(Uri.parse(b['url']).host));
    for (final e in good) {
      print('${e['words']}\t${e['paras']}\t${Uri.parse(e['url']).host}\t${e['title']}');
    }
  }
}

Future<void> push() async {
  final data = loadScan();
  // Add the two properties; existing ones are left as they are.
  await notion('PATCH', 'databases/$sourcesDb', {
    'properties': {
      'Nightly read': {'checkbox': {}},
      'Words': {'number': {'format': 'number'}},
    },
  });
  final rows = await allRows();
  var changed = 0, kept = 0;
  for (final r in rows) {
    final e = data[r['url']] as Map?;
    if (e == null) continue; // Never scanned (videos, searches…): leave it to the user.
    // A tick changed by hand since our last push wins over the scan.
    if (e['pushed'] != null && r['nightly'] != e['pushed']) {
      kept++;
      continue;
    }
    final usable = rejectReason(e) == null;
    final words = e['err'] != null ? null : e['words'] as int;
    // Only usable rows carry a word count, which keeps this to a few hundred calls.
    if (r['nightly'] == usable && (!usable || r['wordsProp'] == words)) {
      e['pushed'] = usable;
      continue;
    }
    await notion('PATCH', 'pages/${r['id']}', {
      'properties': {
        'Nightly read': {'checkbox': usable},
        'Words': {'number': words},
      },
    });
    e['pushed'] = usable;
    if (++changed % 20 == 0) {
      saveScan(data);
      stdout.write('\r$changed updated');
    }
  }
  saveScan(data);
  print('\r$changed rows updated in Notion; $kept hand-edited rows left as they are');
}

/// Reports what changed in Notion since the last push, and anything the app relies on that is missing.
Future<void> check() async {
  final db = await notion('GET', 'databases/$sourcesDb');
  final title = [for (final t in (db['title'] as List).cast<Map>()) t['plain_text']].join();
  print('Database "$title"${db['archived'] == true || db['in_trash'] == true ? ' (IN TRASH)' : ''}, '
      'last edited ${db['last_edited_time']}');
  final props = (db['properties'] as Map).cast<String, dynamic>();
  const needed = {
    'Name': 'title', 'URL': 'url', 'Type': 'select', 'Status': 'select', 'Language': 'select',
    'Chrome group': 'rich_text', 'Nightly read': 'checkbox', 'Words': 'number',
  };
  var problems = 0;
  needed.forEach((name, type) {
    final p = props[name] as Map?;
    if (p == null) {
      print('  MISSING property "$name" ($type)');
      problems++;
    } else if (p['type'] != type) {
      print('  property "$name" is now ${p['type']}, expected $type');
      problems++;
    }
  });
  final statuses = [
    for (final o in ((props['Status'] as Map?)?['select']?['options'] as List? ?? const []).cast<Map>()) o['name']
  ];
  for (final s in ['Read', 'Skip', 'Synthesized']) {
    if (!statuses.contains(s)) print('  Status has no "$s" option (statuses now: $statuses)');
  }
  final extra = props.keys.where((k) => !needed.containsKey(k) && !const {'Path order', 'Origin', 'Inquiry'}.contains(k));
  if (extra.isNotEmpty) print('  new properties: ${extra.join(', ')}');
  print(problems == 0 ? 'Properties: all present' : 'Properties: $problems problem(s); the app needs these');

  final rows = await allRows();
  final data = loadScan();
  final byId = {for (final e in data.values.cast<Map>()) e['id']: e};
  final ticked = rows.where((r) => r['nightly'] == true).toList();
  final open = ticked.where((r) => !const {'Read', 'Skip', 'Synthesized'}.contains(r['status'])).length;
  final status = <String, int>{};
  for (final r in ticked) {
    final k = '${r['status']}';
    status[k] = (status[k] ?? 0) + 1;
  }
  print('\nRows: ${rows.length} (${data.length} were scanned at push time)');
  print('Ticked "Nightly read": ${ticked.length}; the app can offer $open of them. By status: $status');

  final handOn = <Map>[], handOff = <Map>[], fresh = <Map>[], moved = <Map>[];
  for (final r in rows) {
    final e = data[r['url']] as Map?;
    if (e == null) {
      final old = byId[r['id']];
      if (old != null) {
        moved.add(r);
      } else if (readableTypes.contains(r['type'])) {
        fresh.add(r);
      }
      continue;
    }
    if (e['pushed'] != null && r['nightly'] != e['pushed']) (r['nightly'] == true ? handOn : handOff).add(r);
  }
  final liveIds = rows.map((r) => r['id']).toSet();
  final gone = data.values.cast<Map>().where((e) => e['pushed'] == true && !liveIds.contains(e['id'])).toList();
  void list(String label, List<Map> xs) {
    print('$label: ${xs.length}');
    for (final x in xs.take(15)) {
      print('    ${x['title']}  <${x['url']}>');
    }
    if (xs.length > 15) print('    …');
  }

  list('Ticked by hand since the push', handOn);
  list('Unticked by hand since the push', handOff);
  list('New rows not scanned yet (run scan, then push)', fresh);
  list('Rows whose URL changed (rescan to re-measure)', moved);
  list('Ticked rows deleted from Notion', gone);
}

Future<void> main(List<String> args) async {
  final cmd = args.isEmpty ? 'report' : args.first;
  // Honour HTTPS_PROXY / HTTP_PROXY, which dart:io ignores by default.
  Net.client = IOClient(HttpClient()..findProxy = HttpClient.findProxyFromEnvironment);
  if (cmd != 'report') {
    token = Platform.environment['NOTION_TOKEN'] ??
        File('../../notion/.env')
            .readAsLinesSync()
            .firstWhere((l) => l.startsWith('NOTION_TOKEN='))
            .substring('NOTION_TOKEN='.length)
            .trim();
  }
  switch (cmd) {
    case 'scan':
      await scan();
    case 'report':
      report(verbose: args.contains('-v'));
    case 'push':
      await push();
    case 'check':
      await check();
    default:
      print('usage: dart run tool/atlas_nightly.dart scan | report [-v] | push | check');
  }
  exit(0);
}
