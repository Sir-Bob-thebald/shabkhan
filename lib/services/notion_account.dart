import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'net.dart';

/// One row of the Reading Atlas "Sources" database.
class AtlasItem {
  final String pageId;
  final String title;
  final String url;

  /// 'fa' or 'en', from the row's Language property.
  final String lang;

  /// The Chrome tab group or OneTab group it came from, if any.
  final String? group;

  const AtlasItem({required this.pageId, required this.title, required this.url, required this.lang, this.group});

  Map<String, dynamic> toJson() => {'pageId': pageId, 'title': title, 'url': url, 'lang': lang, 'group': group};

  factory AtlasItem.fromJson(Map<String, dynamic> j) => AtlasItem(
        pageId: j['pageId'] as String,
        title: j['title'] as String,
        url: j['url'] as String,
        lang: j['lang'] as String? ?? 'en',
        group: j['group'] as String?,
      );
}

/// A database shared with the connection that has a "Nightly read" checkbox.
class NotionDatabase {
  final String id;
  final String title;
  const NotionDatabase(this.id, this.title);
}

/// The user's Notion connection, used to read the Reading Atlas built by
/// `notion/atlas.py`. It comes either from "Connect with Notion" (OAuth, when
/// the app was built with a public integration's client ID and secret) or
/// from a pasted internal-integration secret. The token is kept in secure
/// storage and is only ever sent to api.notion.com. No database ID is built
/// in: the connection finds the database by its "Nightly read" checkbox.
class NotionAccount {
  static const apiHost = 'api.notion.com';
  static const _version = '2022-06-28';

  /// A public integration's credentials, given at build time:
  ///   flutter build apk --dart-define=NOTION_CLIENT_ID=… --dart-define=NOTION_CLIENT_SECRET=…
  static const clientId = String.fromEnvironment('NOTION_CLIENT_ID');
  static const clientSecret = String.fromEnvironment('NOTION_CLIENT_SECRET');

  /// Must match a redirect URI of the public integration. Never loaded: the
  /// sign-in WebView catches the redirect and takes the code from it.
  static const redirectUri =
      String.fromEnvironment('NOTION_REDIRECT_URI', defaultValue: 'https://localhost/nightly-reader/notion');

  static bool get oauthAvailable => clientId.isNotEmpty && clientSecret.isNotEmpty;

  /// Notion's own sign-in page, where the user also picks the pages to share.
  static Uri authorizeUrl(String state) => Uri.https(apiHost, '/v1/oauth/authorize', {
        'client_id': clientId,
        'response_type': 'code',
        'owner': 'user',
        'redirect_uri': redirectUri,
        'state': state,
      });

  /// The checkbox that `tool/atlas_nightly.dart` ticks on rows that work as a
  /// nightly read (short prose: articles, Wikipedia entries, essays…). It can
  /// also be ticked or cleared by hand in Notion.
  static const nightlyProperty = 'Nightly read';

  /// Rows with these statuses are no longer offered.
  static const doneStatuses = ['Skip', 'Read', 'Synthesized'];

  static const _tokenKey = 'notion.token';
  static const _storage = FlutterSecureStorage();
  static const _cacheFor = Duration(hours: 12);

  SharedPreferences? _prefs;
  String? _token;
  bool get signedIn => _token != null;

  String? get databaseId => _prefs?.getString('notion:db');
  String? get databaseTitle => _prefs?.getString('notion:dbTitle');

  /// The databases found when connecting, so the user can switch between them.
  List<NotionDatabase> get databases => [
        for (final e in (jsonDecode(_prefs?.getString('notion:dbs') ?? '[]') as List).cast<Map>())
          NotionDatabase(e['id'] as String, e['title'] as String),
      ];

  /// Whether finishing a reading sets its Status to "Read" in Notion.
  bool get syncRead => _prefs?.getBool('notion:syncRead') ?? true;
  Future<void> setSyncRead(bool v) async => _prefs?.setBool('notion:syncRead', v);

  Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;
    try {
      _token = await _storage.read(key: _tokenKey);
    } on Exception {
      _token = null; // Keychain/keystore unavailable: behave as disconnected.
    }
  }

  /// Accepts a bare ID, a `Name-<id>` slug or a full notion.so URL.
  static String? parseId(String input) {
    final m = RegExp(r'[0-9a-fA-F]{32}').firstMatch(input.replaceAll('-', ''));
    return m?.group(0)?.toLowerCase();
  }

  /// Saves the token, then finds the databases it can see that have a
  /// "Nightly read" checkbox and uses [database] or the first of them.
  Future<void> signIn(String token, {String? database}) async {
    _token = token.trim();
    await _storage.write(key: _tokenKey, value: _token);
    await _prefs?.remove('notion:items');
    final found = await nightlyDatabases();
    if (found.isEmpty) {
      throw SourceException('No database with a "$nightlyProperty" checkbox is shared with this connection. '
          'Share the atlas\'s Sources database with it and try again.');
    }
    await _prefs?.setString('notion:dbs', jsonEncode([for (final d in found) {'id': d.id, 'title': d.title}]));
    final wanted = database == null ? null : parseId(database);
    await useDatabase(found.firstWhere((d) => d.id == wanted, orElse: () => found.first));
  }

  Future<void> useDatabase(NotionDatabase db) async {
    await _prefs?.setString('notion:db', db.id);
    await _prefs?.setString('notion:dbTitle', db.title);
    await _prefs?.remove('notion:items');
    await _prefs?.remove('notion:itemsAt');
  }

  Future<void> signOut() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
    for (final k in ['notion:items', 'notion:itemsAt', 'notion:db', 'notion:dbTitle', 'notion:dbs']) {
      await _prefs?.remove(k);
    }
  }

  /// Turns the code from Notion's sign-in page into an access token.
  static Future<String> exchangeCode(String code) async {
    final res = await Net.client
        .post(
          Uri.https(apiHost, '/v1/oauth/token'),
          headers: {
            'Authorization': 'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}',
            'Content-Type': 'application/json',
            'Notion-Version': _version,
          },
          body: jsonEncode({'grant_type': 'authorization_code', 'code': code, 'redirect_uri': redirectUri}),
        )
        .timeout(const Duration(seconds: 30));
    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (!text.trimLeft().startsWith('{')) {
      throw SourceException(res.statusCode == 403
          ? 'Notion blocked this connection (it refuses Iranian IPs); turn on a VPN and try again'
          : 'Notion sent an unexpected page (HTTP ${res.statusCode})');
    }
    final data = jsonDecode(text) as Map<String, dynamic>;
    final token = data['access_token'] as String?;
    if (res.statusCode != 200 || token == null) {
      throw SourceException('Notion sign-in failed: ${data['error_description'] ?? data['message'] ?? data['error']}');
    }
    return token;
  }

  /// Databases visible to the connection that have a "Nightly read" checkbox.
  Future<List<NotionDatabase>> nightlyDatabases() async {
    final found = <NotionDatabase>[];
    String? cursor;
    do {
      final data = await call('POST', 'search', {
        'filter': {'property': 'object', 'value': 'database'},
        'page_size': 100,
        'start_cursor': ?cursor,
      });
      for (final db in (data['results'] as List).cast<Map>()) {
        final props = (db['properties'] as Map?) ?? const {};
        if ((props[nightlyProperty] as Map?)?['type'] != 'checkbox') continue;
        final title = [for (final t in (db['title'] as List? ?? const []).cast<Map>()) t['plain_text'] ?? ''].join();
        found.add(NotionDatabase((db['id'] as String).replaceAll('-', ''), title.isEmpty ? 'Untitled' : title));
      }
      cursor = data['has_more'] == true ? data['next_cursor'] as String? : null;
    } while (cursor != null);
    return found;
  }

  /// One Notion API call. Retries flaky connections, rate limits and 5xx.
  Future<Map<String, dynamic>> call(String method, String path, [Object? body]) async {
    if (_token == null) throw SourceException('Notion is not connected');
    final uri = Uri.https(apiHost, '/v1/$path');
    final headers = {
      'Authorization': 'Bearer $_token',
      'Notion-Version': _version,
      'Content-Type': 'application/json',
    };
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
      final http.Response res;
      try {
        res = await (method == 'PATCH'
                ? Net.client.patch(uri, headers: headers, body: jsonEncode(body))
                : Net.client.post(uri, headers: headers, body: jsonEncode(body ?? {})))
            .timeout(const Duration(seconds: 30));
      } on Exception catch (e) {
        lastError = e; // Dropped TLS handshakes and timeouts are common here; try again.
        continue;
      }
      if (res.statusCode == 429 || res.statusCode >= 500) {
        lastError = 'HTTP ${res.statusCode}';
        continue;
      }
      if (res.statusCode == 401) throw SourceException('Notion rejected the token; connect again in Sources');
      if (res.statusCode == 404) {
        throw SourceException('Notion database not found. Is the integration connected to that page?');
      }
      final text = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (!text.trimLeft().startsWith('{')) {
        // Cloudflare's HTML block page: Notion refuses connections from Iran.
        throw SourceException(res.statusCode == 403
            ? 'Notion blocked this connection (it refuses Iranian IPs); turn on a VPN and try again'
            : 'Notion sent an unexpected page (HTTP ${res.statusCode})');
      }
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (res.statusCode != 200) throw SourceException('Notion: ${data['message'] ?? 'HTTP ${res.statusCode}'}');
      return data;
    }
    throw SourceException('Could not reach Notion ($lastError)');
  }

  /// The rows ticked as a nightly read and not yet finished. Cached for 12 hours;
  /// a stale cache is used when Notion can't be reached.
  Future<List<AtlasItem>> shortSources({bool refresh = false}) async {
    final cached = _cached();
    final at = DateTime.tryParse(_prefs?.getString('notion:itemsAt') ?? '');
    if (!refresh && cached != null && at != null && DateTime.now().difference(at) < _cacheFor) return cached;
    try {
      final items = await _queryAll();
      await _prefs?.setString('notion:items', jsonEncode(items.map((i) => i.toJson()).toList()));
      await _prefs?.setString('notion:itemsAt', DateTime.now().toIso8601String());
      return items;
    } on SourceException {
      if (cached != null && !refresh) return cached;
      rethrow;
    }
  }

  /// Number of short rows from the last successful query, for the Sources tab.
  int? get cachedCount => _cached()?.length;

  /// Languages of the rows from the last successful query.
  Set<String> get cachedLangs => {...?_cached()?.map((i) => i.lang)};

  List<AtlasItem>? _cached() {
    final raw = _prefs?.getString('notion:items');
    if (raw == null) return null;
    return (jsonDecode(raw) as List).map((j) => AtlasItem.fromJson((j as Map).cast())).toList();
  }

  Future<List<AtlasItem>> _queryAll() async {
    final databaseId = this.databaseId;
    if (databaseId == null) throw SourceException('No Notion database chosen; connect Notion again');
    final filter = {
      'and': [
        {'property': nightlyProperty, 'checkbox': {'equals': true}},
        for (final s in doneStatuses) {'property': 'Status', 'select': {'does_not_equal': s}},
      ],
    };
    final items = <AtlasItem>[];
    String? cursor;
    do {
      final data = await call('POST', 'databases/$databaseId/query', {
        'page_size': 100,
        'filter': filter,
        'start_cursor': ?cursor,
      });
      for (final page in (data['results'] as List).cast<Map>()) {
        final item = _item(page);
        if (item != null) items.add(item);
      }
      cursor = data['has_more'] == true ? data['next_cursor'] as String? : null;
    } while (cursor != null);
    return items;
  }

  static AtlasItem? _item(Map page) {
    final props = (page['properties'] as Map).cast<String, dynamic>();
    final url = (props['URL'] as Map?)?['url'] as String?;
    if (url == null || !url.startsWith('http')) return null;
    String plain(String name) => [
          for (final t in ((props[name] as Map?)?[(props[name] as Map?)?['type']] as List? ?? const []).cast<Map>())
            t['plain_text'] ?? '',
        ].join().trim();
    final lang = ((props['Language'] as Map?)?['select'] as Map?)?['name'];
    final group = plain('Chrome group');
    return AtlasItem(
      pageId: page['id'] as String,
      title: plain('Name'),
      url: url,
      lang: lang == 'Persian' ? 'fa' : 'en',
      group: group.isEmpty ? null : group,
    );
  }

  /// Sets the row's Status to "Read" after the user finishes it in the app.
  Future<void> markRead(String url) async {
    final item = _cached()?.where((i) => i.url == url).firstOrNull;
    if (item == null) return;
    await call('PATCH', 'pages/${item.pageId}', {
      'properties': {'Status': {'select': {'name': 'Read'}}},
    });
  }
}
