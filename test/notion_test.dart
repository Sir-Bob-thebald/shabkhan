import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightly_reader/models/reading.dart';
import 'package:nightly_reader/services/library.dart';
import 'package:nightly_reader/services/net.dart';
import 'package:nightly_reader/services/notion_account.dart';
import 'package:nightly_reader/sources/notion_atlas.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _page(int words, {String title = 'Page title'}) =>
    '<html><head><title>$title</title><meta name="author" content="Hannah Arendt"></head>'
    '<body><nav>Menu</nav><article><p>${'word ' * words}</p></article></body></html>';

Map<String, dynamic> _row(String id, String url, {String? name, String lang = 'English'}) => {
      'id': id,
      'properties': {
        'Name': {'type': 'title', 'title': [{'plain_text': name ?? url.replaceFirst('https://', '')}]},
        'URL': {'type': 'url', 'url': url},
        'Language': {'type': 'select', 'select': {'name': lang}},
        'Chrome group': {'type': 'rich_text', 'rich_text': [{'plain_text': 'Banality of Evil'}]},
      },
    };

/// A fake Notion API plus the web pages its rows point to.
class FakeNotion {
  final tokenHosts = <String>{};
  final queries = <Map>[];
  final patches = <String, Map>{};
  final fetchedPages = <String>[];
  final tokenExchanges = <Map>[];
  var flakyCalls = 0;
  var databases = [('otherdb', 'Tasks', false), ('sourcesdb', 'Sources', true)];

  static final pages = {
    'https://ok.example/short': _page(900),
    'https://ok.example/long': _page(9000),
    'https://ok.example/stub': _page(40),
  };

  http.Client get client => MockClient((req) async {
        if (req.headers['Authorization'] != null) tokenHosts.add(req.url.host);
        if (req.url.host == NotionAccount.apiHost) {
          if (flakyCalls > 0) {
            flakyCalls--;
            throw http.ClientException('Connection closed during handshake');
          }
          final path = req.url.path;
          if (path == '/v1/oauth/token') {
            tokenExchanges.add(jsonDecode(req.body) as Map);
            return req.headers['Authorization']!.startsWith('Basic ')
                ? http.Response('{"access_token":"ntn_good","workspace_name":"Mine"}', 200)
                : http.Response('{"error":"invalid_client"}', 401);
          }
          if (req.headers['Authorization'] != 'Bearer ntn_good') return http.Response('{"message":"bad"}', 401);
          if (path == '/v1/search') {
            return http.Response(
                jsonEncode({
                  'results': [
                    for (final (id, title, nightly) in databases)
                      {
                        'object': 'database',
                        'id': id,
                        'title': [{'plain_text': title}],
                        'properties': {
                          'Name': {'type': 'title'},
                          if (nightly) 'Nightly read': {'type': 'checkbox'},
                        },
                      },
                  ],
                  'has_more': false,
                }),
                200);
          }
          if (path.endsWith('/query') && !path.contains('/sourcesdb/')) return http.Response('{"message":"x"}', 404);
          if (req.method == 'POST' && path.endsWith('/query')) {
            final body = jsonDecode(req.body) as Map;
            queries.add(body);
            final second = body['start_cursor'] == 'c2';
            return http.Response(
                jsonEncode({
                  'results': second
                      ? [_row('p3', 'https://ok.example/stub'), _row('p4', 'https://ok.example/file.pdf')]
                      : [_row('p1', 'https://ok.example/short'), _row('p2', 'https://ok.example/long')],
                  'has_more': !second,
                  'next_cursor': second ? null : 'c2',
                }),
                200);
          }
          if (req.method == 'PATCH' && path.startsWith('/v1/pages/')) {
            patches[path.split('/').last] = jsonDecode(req.body) as Map;
            return http.Response('{}', 200);
          }
          return http.Response('{"message":"not found"}', 404);
        }
        fetchedPages.add(req.url.toString());
        final html = pages[req.url.toString()];
        return html == null ? http.Response('gone', 404) : http.Response(html, 200);
      });
}

void main() {
  late FakeNotion fake;

  setUp(() {
    fake = FakeNotion();
    Net.client = fake.client;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('database IDs are read from links, slugs and dashed IDs', () {
    const id = '0123456789abcdef0123456789abcdef';
    expect(NotionAccount.parseId(id), id);
    expect(NotionAccount.parseId('01234567-89ab-cdef-0123-456789abcdef'), id);
    expect(NotionAccount.parseId('https://www.notion.so/Sources-$id?v=123'), id);
    expect(NotionAccount.parseId('nonsense'), isNull);
  });

  test('connecting queries only rows ticked Nightly read and unfinished, across all pages', () async {
    final lib = await Library.load();
    final n = await lib.connectNotion('ntn_good');
    expect(n, 4);
    expect(lib.sources.whereType<NotionAtlasSource>(), hasLength(1));
    final filter = jsonEncode(fake.queries.first['filter']);
    expect(filter, contains('{"property":"Nightly read","checkbox":{"equals":true}}'));
    for (final s in ['Skip', 'Read', 'Synthesized']) {
      expect(filter, contains('"does_not_equal":"$s"'));
    }
    expect(fake.queries, hasLength(2));
  });

  test('the database is found by its Nightly read checkbox; no ID is built in', () async {
    final lib = await Library.load();
    await lib.connectNotion('ntn_good');
    expect(lib.notion.databaseId, 'sourcesdb');
    expect(lib.notion.databaseTitle, 'Sources');
    expect(lib.notion.databases.map((d) => d.title), ['Sources']);
  });

  test('without a shared database that has the checkbox, connecting explains what to share', () async {
    fake.databases = [('otherdb', 'Tasks', false)];
    final lib = await Library.load();
    await expectLater(lib.connectNotion('ntn_good'),
        throwsA(isA<SourceException>().having((e) => e.message, 'message', contains('Share the atlas'))));
    expect(lib.notion.signedIn, isFalse);
  });

  test('with several matching databases the first is used and the others can be chosen', () async {
    fake.databases = [('sourcesdb', 'Sources', true), ('seconddb', 'Old atlas', true)];
    final lib = await Library.load();
    await lib.connectNotion('ntn_good');
    expect(lib.notion.databases, hasLength(2));
    expect(lib.notion.databaseId, 'sourcesdb');
  });

  test('"Connect with Notion" swaps the sign-in code for a token', () async {
    final lib = await Library.load();
    expect(await lib.connectNotionWithCode('the-code'), 4);
    expect(lib.notion.signedIn, isTrue);
    expect(fake.tokenExchanges.single, {
      'grant_type': 'authorization_code',
      'code': 'the-code',
      'redirect_uri': NotionAccount.redirectUri,
    });
    final url = NotionAccount.authorizeUrl('xyz');
    expect(url.host, NotionAccount.apiHost);
    expect(url.queryParameters, containsPair('owner', 'user'));
    expect(url.queryParameters, containsPair('state', 'xyz'));
  });

  test('the browser sign-in comes back by the app link and must answer our own request', () async {
    final lib = await Library.load();
    final start = await lib.startNotionSignIn();
    expect(start.queryParameters['redirect_uri'], 'com.nightlyreader.shabkhan://oauth/notion');
    final state = start.queryParameters['state']!;

    // A reply with another state (not started by this app) is refused.
    final forged = Uri.parse('${NotionAccount.redirectUri}?code=x&state=nope');
    expect(Library.isNotionCallback(forged), isTrue);
    await expectLater(lib.finishNotionSignIn(forged), throwsA(isA<SourceException>()));
    expect(lib.notion.signedIn, isFalse);

    final again = await lib.startNotionSignIn();
    final reply = Uri.parse('${NotionAccount.redirectUri}?code=the-code&state=${again.queryParameters['state']}');
    expect(state, isNot(again.queryParameters['state']));
    expect(await lib.finishNotionSignIn(reply), 4);
    expect(lib.notion.signedIn, isTrue);
    // The state is single-use.
    await expectLater(lib.finishNotionSignIn(reply), throwsA(isA<SourceException>()));
    expect(Library.isNotionCallback(Uri.parse('https://example.com/?code=1')), isFalse);
  });

  test('a token that cannot read the database is discarded', () async {
    final lib = await Library.load();
    await expectLater(lib.connectNotion('ntn_bad'), throwsA(isA<SourceException>()));
    expect(lib.notion.signedIn, isFalse);
    expect(lib.sources.whereType<NotionAtlasSource>(), isEmpty);
  });

  test('a Cloudflare block says so, and the saved list keeps the source working', () async {
    final lib = await Library.load();
    await lib.connectNotion('ntn_good');
    // Make the saved list stale, then have Notion answer with its HTML block page.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notion:itemsAt', DateTime(2020).toIso8601String());
    Net.client = MockClient((req) async => req.url.host == NotionAccount.apiHost
        ? http.Response('<!DOCTYPE html><title>Attention Required! | Cloudflare</title>', 403)
        : fake.client.send(req).then(http.Response.fromStream));
    expect((await lib.notion.shortSources()).length, 4);
    await expectLater(
        lib.refreshNotion(), throwsA(isA<SourceException>().having((e) => e.message, 'message', contains('VPN'))));
  });

  test('dropped connections to Notion are retried', () async {
    final lib = await Library.load();
    fake.flakyCalls = 2;
    expect(await lib.connectNotion('ntn_good'), 4);
  });

  test('only pages of 300-4000 words are offered; long, stub and file links are dropped', () async {
    final lib = await Library.load();
    await lib.connectNotion('ntn_good');
    for (var i = 0; i < 6; i++) {
      final r = await lib.atlas.fetch(Random(i));
      expect(r.url, 'https://ok.example/short');
      expect(r.type, ReadingType.essay);
      expect(r.title, 'Page title'); // The atlas name was only the URL.
      expect(r.author, 'Hannah Arendt');
      expect(r.sourceName, 'Reading Atlas · Banality of Evil');
      expect(r.body, isNot(contains('Menu')));
    }
    expect(fake.fetchedPages, isNot(contains('https://ok.example/file.pdf')));
    // Rejected pages are remembered and not downloaded again.
    expect(fake.fetchedPages.where((u) => u.endsWith('/long')), hasLength(1));
    expect(fake.fetchedPages.where((u) => u.endsWith('/stub')), hasLength(1));
  });

  test('finishing a Notion reading marks it Read in the atlas, unless switched off', () async {
    final lib = await Library.load();
    await lib.connectNotion('ntn_good');
    final r = await lib.atlas.fetch(Random(1));
    lib.tonight.readings[ReadingType.essay] = r;
    await lib.setFinished(lib.tonight, ReadingType.essay, true);
    expect(jsonEncode(fake.patches['p1']), contains('"Status":{"select":{"name":"Read"}}'));

    fake.patches.clear();
    await lib.setNotionSyncRead(false);
    await lib.setFinished(lib.tonight, ReadingType.essay, true);
    expect(fake.patches, isEmpty);
  });

  test('the token is only ever sent to api.notion.com', () async {
    final lib = await Library.load();
    await lib.connectNotion('ntn_good');
    for (var i = 0; i < 3; i++) {
      await lib.atlas.fetch(Random(i));
    }
    expect(fake.tokenHosts, {NotionAccount.apiHost});
  });

  test('the connection survives a restart; disconnecting forgets it', () async {
    final lib = await Library.load();
    await lib.connectNotion('ntn_good');
    expect((await Library.load()).notion.signedIn, isTrue);
    await lib.disconnectNotion();
    final reloaded = await Library.load();
    expect(reloaded.notion.signedIn, isFalse);
    expect(reloaded.notion.cachedCount, isNull);
  });
}
