import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightly_reader/models/reading.dart';
import 'package:nightly_reader/services/library.dart';
import 'package:nightly_reader/services/net.dart';
import 'package:nightly_reader/services/substack_account.dart';
import 'package:nightly_reader/sources/substack.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _essayHtml = '<p>${'A sentence worth reading tonight, about how we think. ' * 60}</p>';
final _poemHtml = [for (var i = 0; i < 16; i++) '<p>the moon leans on line $i</p>'].join();

Map<String, dynamic> _sub(int id, String name, String sub, String state) => {
      'membership_state': state,
      'visibility': 'public',
      'publication': {'id': id, 'name': name, 'subdomain': sub},
    };

/// A fake Substack that records which hosts saw the session cookie.
class FakeSubstack {
  final cookieHosts = <String>{};
  final requestedPosts = <String>[];
  var subscriptions = [
    _sub(1, 'Zeta Letters', 'zeta', 'free_signup'),
    _sub(2, 'Alpha Fiction', 'alpha', 'subscribed_paid'),
    // A reader's own profile: followed, but it never posts.
    _sub(3, 'Quiet Reader', 'quiet', 'free_signup'),
  ];

  http.Client get client => MockClient((req) async {
        if (req.headers['Cookie'] != null) cookieHosts.add(req.url.host);
        final path = req.url.path;
        if (path == '/api/v1/user/reader/public_profile') {
          return http.Response(jsonEncode({'handle': 'reader', 'subscriptions': subscriptions}), 200);
        }
        if (path.startsWith('/api/v1/user/')) return http.Response('{"error":"not found"}', 404);
        if (path == '/api/v1/subscriptions') {
          return req.headers['Cookie'] == 'substack.sid=good'
              ? http.Response('{"subscriptions":[]}', 200)
              : http.Response('{"errors":[{"msg":"Please sign in"}]}', 401);
        }
        if (path == '/api/v1/archive') {
          if (req.url.host == 'quiet.substack.com') return http.Response('[]', 200);
          return http.Response(
              jsonEncode([
                {'id': 10, 'type': 'newsletter', 'audience': 'only_paid', 'wordcount': 1500, 'title': 'Paid'},
                {'id': 11, 'type': 'newsletter', 'audience': 'everyone', 'wordcount': 1500, 'title': 'Free essay', 'post_date': '2026-10-30T08:00:00.000Z'},
                {'id': 12, 'type': 'podcast', 'audience': 'everyone', 'wordcount': 1500, 'title': 'Pod'},
                {'id': 13, 'type': 'newsletter', 'audience': 'everyone', 'wordcount': 90, 'title': 'Night'},
              ]),
              200);
        }
        if (path.startsWith('/api/v1/posts/by-id/')) {
          final id = path.split('/').last;
          requestedPosts.add(id);
          return http.Response(
              jsonEncode({
                'post': {
                  'title': 'Post $id',
                  'body_html': id == '13' ? _poemHtml : _essayHtml,
                  'canonical_url': 'https://zeta.substack.com/p/$id',
                  'publishedBylines': [
                    {'name': 'Writer'}
                  ],
                }
              }),
              200);
        }
        return http.Response('not found', 404);
      });
}

void main() {
  late FakeSubstack fake;

  setUp(() {
    fake = FakeSubstack();
    Net.client = fake.client;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('usernames are read from @names, profile links and publication hosts', () {
    for (final input in ['reader', '@reader', 'https://substack.com/@reader', 'substack.com/profile/123-reader',
        'reader.substack.com', ' @reader ']) {
      expect(SubstackAccount.parseHandle(input), 'reader', reason: input);
    }
    expect(SubstackAccount.parseHandle('https://substack.com/'), isNull);
    expect(SubstackAccount.parseHandle('two words'), isNull);
  });

  test('connecting with a username lists follows without signing in, as one source', () async {
    final lib = await Library.load();
    expect(await lib.connectSubstack('@reader'), 2);
    expect(lib.substack.signedIn, isFalse);
    expect(lib.substackPubs.map((p) => p.name), ['Alpha Fiction', 'Zeta Letters']);
    expect(lib.substackPubs.first.paid, isTrue);
    expect(lib.substackPubs.first.host, 'alpha.substack.com');
    expect(lib.sources.whereType<SubstackSource>(), hasLength(1));
    expect(lib.substackSource.types, ReadingType.values.toSet());
  });

  test('only publications that post are listed, each with its latest post and its page', () async {
    final lib = await Library.load();
    await lib.connectSubstack('reader');
    expect(lib.substackPubs.map((p) => p.name), isNot(contains('Quiet Reader')));
    final alpha = lib.substackPubs.first;
    // The paid post (id 10) comes first in the archive and has no date; the latest dated one is used.
    expect(alpha.lastPost, DateTime.parse('2026-10-30T08:00:00.000Z'));
    expect(alpha.page.toString(), 'https://alpha.substack.com');
    final reloaded = await Library.load();
    expect(reloaded.substackPubs.first.lastPost, alpha.lastPost);
  });

  test('unknown users and hidden follow lists say what is wrong', () async {
    final lib = await Library.load();
    await expectLater(lib.connectSubstack('nobody'),
        throwsA(isA<SourceException>().having((e) => e.message, 'message', contains('No Substack user'))));
    fake.subscriptions = [];
    await expectLater(lib.connectSubstack('reader'),
        throwsA(isA<SourceException>().having((e) => e.message, 'message', contains('visible on your profile'))));
    expect(lib.substackHandle, isNull);
  });

  test('posts are sorted by content, and each verdict is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const pub = SubstackPub(id: 1, name: 'Zeta', host: 'zeta.substack.com', paid: false);
    final source = SubstackSource(() => [pub], SubstackAccount(), prefs);
    for (var i = 0; i < 6; i++) {
      expect((await source.fetchFor(ReadingType.poem, Random(i))).title, 'Post 13');
      final essay = await source.fetchFor(ReadingType.essay, Random(i));
      expect(essay.title, 'Post 11');
      expect(essay.type, ReadingType.essay);
    }
    // Once sorted, a post isn't fetched again just to be turned down.
    expect(fake.requestedPosts.where((id) => id == '11').length, lessThanOrEqualTo(7));
    expect(jsonDecode(prefs.getString('substack:kinds')!), {'11': 'essay', '13': 'poem'});
    await expectLater(source.fetchFor(ReadingType.story, Random(1)), throwsA(isA<SourceException>()));
  });

  test('a publication can be pinned to one type or switched off', () async {
    final lib = await Library.load();
    await lib.connectSubstack('reader');
    for (final p in lib.substackPubs) {
      await lib.setSubstackPub(p, type: () => ReadingType.story);
    }
    expect(lib.substackSource.types, {ReadingType.story});
    final r = await lib.substackSource.fetchFor(ReadingType.story, Random(1));
    expect(r.type, ReadingType.story);
    for (final p in lib.substackPubs) {
      await lib.setSubstackPub(p, on: false);
    }
    expect(lib.substackSource.types, isEmpty);
  });

  test('settings survive a refresh and a restart', () async {
    final lib = await Library.load();
    await lib.connectSubstack('reader');
    await lib.setSubstackPub(lib.substackPubs.first, type: () => ReadingType.poem, on: false);
    await lib.refreshSubstack();
    final reloaded = await Library.load();
    expect(reloaded.substackHandle, 'reader');
    expect(reloaded.substackPubs.first.type, ReadingType.poem);
    expect(reloaded.substackPubs.first.on, isFalse);
    expect(reloaded.substackPubs.last.type, isNull);
  });

  test('the optional session is checked, kept, and only ever sent to substack.com', () async {
    final lib = await Library.load();
    await expectLater(lib.signInSubstack('anonymous'), throwsA(isA<SourceException>()));
    expect(lib.substack.signedIn, isFalse);
    await lib.signInSubstack('good');
    expect(lib.substack.signedIn, isTrue);
    const pub = SubstackPub(id: 1, name: 'Zeta', host: 'zeta.substack.com', paid: true);
    for (var i = 0; i < 5; i++) {
      await SubstackSource(() => [pub], lib.substack).fetchFor(ReadingType.essay, Random(i));
    }
    expect(fake.cookieHosts, {'substack.com'});
  });

  test('without a paid subscription, paid posts and podcasts are skipped', () async {
    const pub = SubstackPub(id: 1, name: 'Zeta', host: 'zeta.substack.com', paid: false, type: ReadingType.essay);
    for (var i = 0; i < 8; i++) {
      final r = await SubstackSource(() => [pub], SubstackAccount()).fetchFor(ReadingType.essay, Random(i));
      expect(r.title, 'Post 11');
      expect(r.author, 'Writer');
      expect(r.sourceName, 'Zeta');
    }
    expect(fake.requestedPosts.toSet(), {'11'});
  });

  test('disconnecting forgets the username, publications and session', () async {
    final lib = await Library.load();
    await lib.connectSubstack('reader');
    await lib.signInSubstack('good');
    await lib.disconnectSubstack();
    final reloaded = await Library.load();
    expect(reloaded.substackHandle, isNull);
    expect(reloaded.substack.signedIn, isFalse);
    expect(reloaded.substackPubs, isEmpty);
    expect(reloaded.sources.whereType<SubstackSource>(), isEmpty);
  });
}
