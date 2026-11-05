// Hits the real sources over the network, so these are opt-in:
//   flutter test test/sources_live_test.dart
@Tags(['live'])
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightly_reader/models/languages.dart';
import 'package:nightly_reader/models/reading.dart';
import 'package:nightly_reader/services/art_finder.dart';
import 'package:nightly_reader/services/notion_account.dart';
import 'package:nightly_reader/services/substack_account.dart';
import 'package:nightly_reader/services/translator.dart';
import 'package:nightly_reader/sources/feed.dart';
import 'package:nightly_reader/sources/notion_atlas.dart';
import 'package:nightly_reader/sources/registry.dart';
import 'package:nightly_reader/sources/substack.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final rng = Random();

  // Every catalog source, for every type it can supply.
  for (final entry in catalog()) {
    final source = entry.source;
    for (final type in source.types) {
      test('${source.name} returns a readable ${type.name}', () async {
        final r = await source.fetchFor(type, rng);
        // ignore: avoid_print
        print('[${source.id}/${type.name}] ${r.title} — ${r.author} (${r.wordCount} words, ${r.lang})\n'
            '${r.body.substring(0, min(200, r.body.length))}\n');
        expect(r.title, isNotEmpty);
        expect(r.body.length, greaterThan(80));
        expect(r.type, type);
        expect(r.url, startsWith('http'));
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  }

  test('follows come from a public Substack profile, and posts are sorted by content', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final account = SubstackAccount();
    final pubs = await account.follows('scottalexander');
    // ignore: avoid_print
    print('[substack] follows: ${pubs.map((p) => '${p.name} (${p.host})').join(', ')}');
    expect(pubs, isNotEmpty);
    final source = SubstackSource(() => pubs, account, prefs);
    final r = await source.fetchFor(ReadingType.essay, rng);
    // ignore: avoid_print
    print('[substack] ${r.sourceName}: ${r.title} (${r.wordCount} words)');
    expect(r.body.length, greaterThan(800));
    // ignore: avoid_print
    print('[substack] remembered kinds: ${prefs.getString('substack:kinds')}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a public-domain painting is found for readings in several languages', () async {
    for (final id in ['ganjoor-hafez', 'wikisource-de-gedicht', 'ganjoor-golestan', 'paulgraham']) {
      final r = await catalog().firstWhere((e) => e.id == id).source.fetchFor(
          catalog().firstWhere((e) => e.id == id).source.type, rng);
      final art = await ArtFinder.find(r, rng);
      // ignore: avoid_print
      print('[art] ${r.title} (${ArtFinder.hintsFor(r)}) → ${art?.label} · ${art?.date} · ${art?.origin} · ${art?.credit}');
      expect(art, isNotNull);
      expect(art!.imageUrl, startsWith('https://'));
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('most art collections have a picture of the moon that passes the checks', () async {
    final arts = await ArtFinder.eachCollection('moon', rng);
    for (final a in arts) {
      // ignore: avoid_print
      print('[art] ${a == null ? '-' : '${a.credit} · ${a.title}'}');
    }
    // Openverse limits anonymous clients, so one or two may be busy.
    expect(arts.whereType<Object>().length, greaterThanOrEqualTo(arts.length - 2));
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('links are turned into sources: a homepage finds its feed', () async {
    final found = await FeedSource.discover('https://www.themarginalian.org/');
    // ignore: avoid_print
    print('[discover] ${found.url} · ${found.title} · ${found.lang} · site=${found.site}');
    expect(found.site, isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('machine translation works with Google and MyMemory', () async {
    final story = await catalog().firstWhere((e) => e.id == 'ganjoor-golestan').source.fetch(rng);
    final google = await const Translator(TranslatorKind.google).translate(story.body, from: 'fa', to: 'en');
    // ignore: avoid_print
    print('[google fa→en] ${story.body.length} chars → ${google.substring(0, min(300, google.length))}');
    expect(detectLanguage(google), 'en');
    expect('\n\n'.allMatches(google).length, greaterThanOrEqualTo('\n\n'.allMatches(story.body).length ~/ 2));
    final ru = await const Translator(TranslatorKind.google).translate(google, from: 'en', to: 'ru');
    expect(detectLanguage(ru), 'ru');
    final mm = await const Translator(TranslatorKind.myMemory)
        .translate('The fog comes on little cat feet.', from: 'en', to: 'de');
    // ignore: avoid_print
    print('[mymemory en→de] $mm');
    expect(detectLanguage(mm), 'de');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a custom RSS feed sorted by content works', () async {
    const url = 'https://strangehorizons.com/feed/';
    expect(await FeedSource.probe(url), isNotEmpty);
    final feed = FeedSource(id: 'f', name: 'SH', type: null, url: url);
    final r = await feed.fetchFor(ReadingType.story, rng);
    expect(r.body.length, greaterThan(200));
  }, timeout: const Timeout(Duration(minutes: 2)));

  // Read-only: needs NOTION_TOKEN in the environment (the atlas integration secret).
  final notionToken = Platform.environment['NOTION_TOKEN'];
  test('the Reading Atlas is found by its checkbox and returns a short article', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final account = NotionAccount();
    await account.load(prefs);
    await account.signIn(notionToken!);
    // ignore: avoid_print
    print('[notion] databases: ${account.databases.map((d) => d.title)}; using ${account.databaseTitle}');
    final items = await account.shortSources(refresh: true);
    // ignore: avoid_print
    print('[notion] ${items.length} short, unfinished rows');
    expect(items, isNotEmpty);
    final source = NotionAtlasSource(account, prefs);
    for (var i = 0; i < 3; i++) {
      final r = await source.fetch(rng);
      // ignore: avoid_print
      print('[notion] ${r.title} — ${r.author} (${r.wordCount} words, ${r.lang}) ${r.url}');
      expect(r.wordCount, inInclusiveRange(NotionAtlasSource.minWords, NotionAtlasSource.maxWords));
    }
  }, skip: notionToken == null ? 'set NOTION_TOKEN to run' : false, timeout: const Timeout(Duration(minutes: 6)));
}
