// Regressions found in the pre-release review.
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightly_reader/models/artwork.dart';
import 'package:nightly_reader/models/reading.dart';
import 'package:nightly_reader/services/library.dart';
import 'package:nightly_reader/services/net.dart';
import 'package:nightly_reader/sources/feed.dart';
import 'package:nightly_reader/sources/source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A source whose reply has an unexpected shape: the cast fails with a TypeError.
class _Broken extends ReadingSource {
  @override
  String get id => 'broken';
  @override
  String get name => 'Broken';
  @override
  String get description => '';
  @override
  ReadingType get type => ReadingType.essay;
  @override
  String get lang => 'en';
  @override
  Future<Reading> fetch(Random rng) async => (null as dynamic) as Reading;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('a source failing with an Error (not an Exception) gives the card an error instead of hanging', () async {
    Net.client = MockClient((req) async => http.Response('offline', 503));
    final lib = await Library.load();
    for (final s in lib.sources) {
      await lib.setEnabled(s, false);
    }
    await lib.addFeed(name: 'F', url: 'https://f.example/feed', type: ReadingType.essay, lang: 'en');
    // Not something users can add; it stands in for any source with a bad reply.
    expect(_Broken().fetch(Random(1)), throwsA(isA<TypeError>()));
    await lib.ensureTonight();
    expect(lib.errors[ReadingType.essay], isNotNull);
    expect(lib.loading, isEmpty);
  });

  test('a failing feed of unknown language is tried once, not once per language', () async {
    var fetches = 0;
    Net.client = MockClient((req) async {
      if (req.url.host == 'new.example') fetches++;
      return http.Response('down', 503);
    });
    final lib = await Library.load();
    await lib.addFeed(name: 'New', url: 'https://new.example/feed', type: ReadingType.poem);
    await lib.ensureTonight();
    expect(fetches, 1);
  });

  test('text size stays within the slider and is rounded', () async {
    final lib = await Library.load();
    for (var i = 0; i < 6; i++) {
      await lib.setTextScale(lib.textScale - 0.1);
    }
    expect(lib.textScale, Library.minTextScale);
    for (var i = 0; i < 20; i++) {
      await lib.setTextScale(lib.textScale + 0.1);
    }
    expect(lib.textScale, Library.maxTextScale);
  });

  test('a picture missed while offline is looked for again later', () async {
    Net.client = MockClient((req) async => http.Response('offline', 503));
    final lib = await Library.load();
    var online = false;
    lib.findArt = (r, rng) async => online ? const Artwork(imageUrl: 'https://i/a.jpg', title: 'A', credit: 'c') : null;
    lib.tonight.readings[ReadingType.poem] = Reading(
        type: ReadingType.poem, title: 'P', body: 'b', sourceId: 's', sourceName: 'S', url: 'https://p', lang: 'en');
    await lib.ensureTonight();
    await pumpEventQueue();
    expect(lib.tonight.readings[ReadingType.poem]!.art, isNull);
    online = true;
    await lib.ensureTonight();
    await pumpEventQueue();
    expect(lib.tonight.readings[ReadingType.poem]!.art!.title, 'A');
  });

  test('only the newest nights are kept', () async {
    Net.client = MockClient((req) async => http.Response('offline', 503));
    final dates = [for (var i = 0; i < Library.keepNights + 5; i++) '2025-01-${i.toString().padLeft(3, '0')}'];
    SharedPreferences.setMockInitialValues({
      'nights': dates,
      for (final d in dates) 'night:$d': '{"date":"$d","readings":{},"finished":[]}',
    });
    final lib = await Library.load();
    lib.tonight.readings[ReadingType.poem] = Reading(
        type: ReadingType.poem, title: 'P', body: 'b', sourceId: 's', sourceName: 'S', url: 'https://p', lang: 'en');
    await lib.setFinished(lib.tonight, ReadingType.poem, true); // saves tonight
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('nights'), hasLength(Library.keepNights));
    expect(prefs.getString('night:${dates.first}'), isNull);
    expect(prefs.getString('night:${dates.last}'), isNotNull);
  });

  test('feeds declaring a language the app has no name for are detected instead', () async {
    Net.client = MockClient((req) async => http.Response.bytes(
        '<?xml version="1.0"?><rss><channel><title>X</title><language>eng</language>'
                '<item><title>One</title><link>https://x/1</link><description>The night is long and the moon is out tonight.</description></item>'
                '</channel></rss>'
            .codeUnits,
        200));
    expect((await FeedSource.probe('https://x.example/feed')).lang, 'en');
  });

  test('old Substack data without a username is dropped', () async {
    SharedPreferences.setMockInitialValues({
      'substackPubs': ['{"id":1,"name":"Old","host":"old.substack.com","paid":false,"type":"essay"}'],
    });
    final lib = await Library.load();
    expect(lib.substackPubs, isEmpty);
  });
}
