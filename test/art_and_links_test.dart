import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightly_reader/models/artwork.dart';
import 'package:nightly_reader/models/reading.dart';
import 'package:nightly_reader/services/art_finder.dart';
import 'package:nightly_reader/services/art_saver.dart';
import 'package:nightly_reader/services/library.dart';
import 'package:nightly_reader/services/net.dart';
import 'package:nightly_reader/sources/feed.dart';
import 'package:nightly_reader/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Reading _r(String body, {String lang = 'en', String sourceId = 'x', String? author, String title = 'T'}) => Reading(
      type: ReadingType.poem,
      title: title,
      author: author,
      body: body,
      sourceId: sourceId,
      sourceName: 'S',
      url: 'https://x/$title',
      lang: lang,
    );

http.Response _json(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200);

void main() {
  group('choosing a picture', () {
    test('the subject comes from the words, the place from the language, the era from the source', () {
      final hafez = ArtFinder.hintsFor(_r('دوش در حلقهٔ ما قصهٔ گیسوی تو بود، تا دل شب سخن از سلسلهٔ موی تو بود\n'
          'شب قدر است و طی شد نامه هجر، شب‌ها',
          lang: 'fa', sourceId: 'ganjoor-hafez', author: 'حافظ'));
      expect(hafez.subject, 'night');
      expect(hafez.place, 'Iran');
      expect(hafez.era, (from: 1350, to: 1550));

      final german = ArtFinder.hintsFor(_r('Im Wald, im Wald, da wohnt der Fuchs; der Wald ist still.', lang: 'de'));
      expect(german.subject, 'forest');
      expect(german.place, 'Germany');
      expect(german.era, isNull);

      expect(ArtFinder.hintsFor(_r('Nothing pictured here at all.')).subject, 'landscape');
    });

    test('The Met is asked with subject, place and era first, then less; only public-domain works are used', () async {
      final searches = <Map<String, String>>[];
      Net.client = MockClient((req) async {
        if (req.url.path.endsWith('/v1.1/search')) {
          searches.add(req.url.queryParameters);
          // Nothing for the full query; two hits once the era is dropped.
          return _json(req.url.queryParameters.containsKey('dateBegin') ? {'total': 0} : {'total': 2, 'objectIDs': [1, 2]});
        }
        if (req.url.path.endsWith('/objects/1')) return _json({'isPublicDomain': false, 'primaryImageSmall': 'https://img/1.jpg'});
        if (req.url.path.endsWith('/objects/2')) {
          return _json({
            'isPublicDomain': true,
            'primaryImageSmall': 'https://img/2-small.jpg',
            'primaryImage': 'https://img/2.jpg',
            'title': 'Night Garden',
            'artistDisplayName': 'Unknown',
            'objectDate': 'ca. 1600',
            'country': 'Iran',
            'objectURL': 'https://met/2',
          });
        }
        return http.Response('no', 404);
      });
      final art = await ArtFinder.find(
          _r('شب و ماه و شب', lang: 'fa', sourceId: 'ganjoor-hafez'), Random(1));
      expect(art!.title, 'Night Garden');
      expect(art.fullUrl, 'https://img/2.jpg');
      expect(art.credit, contains('Public domain'));
      expect(searches.first, containsPair('q', 'night'));
      expect(searches.first, containsPair('geoLocation', 'Iran'));
      expect(searches.first, containsPair('dateBegin', '1350'));
      expect(searches[1], containsPair('geoLocation', 'Iran'));
      expect(searches[1].containsKey('dateBegin'), isFalse);
    });

    test('pictures come from several collections, not always the same one', () async {
      Net.client = MockClient((req) async => switch (req.url.host) {
            'collectionapi.metmuseum.org' => req.url.path.contains('/objects/')
                ? _json({'isPublicDomain': true, 'primaryImageSmall': 'https://m/1.jpg', 'title': 'Met moon', 'classification': 'Paintings'})
                : _json({'total': 1, 'objectIDs': [1]}),
            'openaccess-api.clevelandart.org' => _json({
                'data': [
                  {'title': 'Cleveland moon', 'type': 'Print', 'images': {'web': {'url': 'https://c/1.jpg'}}}
                ]
              }),
            'api.smk.dk' => _json({
                'items': [
                  {'image_thumbnail': 'https://s/1.jpg', 'public_domain': true, 'titles': [{'title': 'Månelys'}], 'object_names': [{'name': 'Maleri'}]}
                ]
              }),
            'api.europeana.eu' => _json({
                'items': [
                  {
                    'title': ['Europeana moon'],
                    'edmPreview': ['https://e/thumb?uri=x'],
                    'rights': ['http://creativecommons.org/publicdomain/mark/1.0/'],
                  }
                ]
              }),
            'search.artsmia.org' => _json({
                'hits': {
                  'hits': [
                    {
                      '_source': {'id': 5, 'title': 'Moon over water', 'classification': 'Paintings', 'rights_type': 'Public Domain'}
                    }
                  ]
                }
              }),
            'api.openverse.org' => _json({
                'results': [
                  {
                    'title': 'Goose and <em>moon</em>',
                    'license': 'cc0',
                    'thumbnail': 'https://o/t/',
                    'tags': [{'name': 'Moon'}, {'name': 'Paintings'}, {'name': 'England'}],
                  }
                ]
              }),
            _ => http.Response('no', 404),
          });
      final credits = <String>{};
      for (var seed = 0; seed < 60; seed++) {
        credits.add((await ArtFinder.find(_r('The moon at night.'), Random(seed)))!.credit.split(' ').first);
      }
      expect(credits, containsAll(['The', 'Cleveland', 'SMK,', 'Europeana', 'Minneapolis', 'Freer', 'Smithsonian']));
    });

    test('Europeana items that are not public domain are skipped', () async {
      Net.client = MockClient((req) async => req.url.host == 'api.europeana.eu'
          ? _json({
              'items': [
                {
                  'title': ['Licensed'],
                  'edmPreview': ['https://e/t?uri=x'],
                  'rights': ['http://creativecommons.org/licenses/by-sa/4.0/'],
                }
              ]
            })
          : http.Response('no', 404));
      expect(await ArtFinder.find(_r('The moon.'), Random(1)), isNull);
    });

    test('works that name the subject pass, including textiles, sculpture, photos, maps and text pages; pots, coins and strips do not', () async {
      Map item(String title, String type, {int w = 900, int h = 700}) => {
            'title': title,
            'type': type,
            'images': {
              'web': {'url': 'https://c/$title.jpg', 'width': '$w', 'height': '$h'}
            },
          };
      Net.client = MockClient((req) async => req.url.host == 'openaccess-api.clevelandart.org'
          ? _json({
              'data': [
                item('Moon flask', 'Ceramic'),
                item('Coin with crescent moon', 'Coins'),
                item('Moon jar', 'Painting'), // refused by its title whatever the type says
                item('Moon gate', 'Furniture'),
                item('Moon over the pines', 'Painting', w: 216, h: 900), // a hanging scroll: too tall for a card
                item('Portrait of Sarah Moonsworth', 'Painting'), // the word is only part of a name
                item('A garden', 'Painting'), // a good picture of the wrong subject
                item('Moon and Waves', 'Painting'),
                item('The moon rising', 'Photograph'),
                item('Folio from a Qur\'an, moon verse', 'Manuscript'),
                item('Calligraphy of the moon', 'Calligraphy'),
                item('Moon goddess', 'Sculpture'),
                item('Tapestry with the moon', 'Textile'),
                item('Map of the moon', 'Map'),
                item('Fragment of a moon fresco', 'Fragment'),
              ]
            })
          : http.Response('no', 404));
      final chosen = <String>{};
      for (var seed = 0; seed < 80; seed++) {
        chosen.add((await ArtFinder.find(_r('The moon.'), Random(seed)))!.title);
      }
      expect(chosen, {
        'Moon and Waves', 'The moon rising', 'Folio from a Qur\'an, moon verse', 'Calligraphy of the moon', //
        'Moon goddess', 'Tapestry with the moon', 'Map of the moon', 'Fragment of a moon fresco',
      });
    });

    test('Openverse museums are checked for place and era by their tags', () async {
      Map item(String title, List<String> tags) => {
            'title': title,
            'license': 'cc0',
            'thumbnail': 'https://o/$title/',
            'tags': [for (final t in tags) {'name': t}],
          };
      Net.client = MockClient((req) async => req.url.host == 'api.openverse.org'
          ? _json({
              'results': [
                item('Night, Chinese', ['Night', 'Paintings', 'China', '1400s']),
                item('Night, Persian, too late', ['Night', 'Paintings', 'Iran', '1800s']),
                item('Night, Persian', ['Night', 'Manuscripts', 'Iran', '1400s']),
              ]
            })
          : http.Response('no', 404));
      final art = await ArtFinder.find(_r('شب و ماه و شب', lang: 'fa', sourceId: 'ganjoor-hafez'), Random(1));
      expect(art!.title, 'Night, Persian');
      expect(art.imageUrl, 'https://o/Night, Persian/');
    });

    test('offline, no picture is found and nothing breaks', () async {
      Net.client = MockClient((req) async => throw http.ClientException('offline'));
      expect(await ArtFinder.find(_r('The moon.'), Random(1)), isNull);
    });

    test('Wikimedia Commons is the fallback, public domain only', () async {
      Net.client = MockClient((req) async {
        if (req.url.host.contains('metmuseum')) return _json({'total': 0});
        return _json({
          'query': {
            'pages': {
              '1': {
                'title': 'File:Modern.jpg',
                'imageinfo': [
                  {'thumburl': 'https://c/m.jpg', 'extmetadata': {'LicenseShortName': {'value': 'CC BY-SA 4.0'}}}
                ]
              },
              '2': {
                'title': 'File:Old.jpg',
                'imageinfo': [
                  {
                    'thumburl': 'https://c/o.jpg',
                    'url': 'https://c/o-full.jpg',
                    'extmetadata': {
                      'LicenseShortName': {'value': 'Public domain'},
                      'ObjectName': {'value': 'Moonrise'},
                      'Categories': {'value': 'Paintings by Caspar David Friedrich|Moon in art'},
                      'Artist': {'value': '<a href="x">Caspar David Friedrich</a>'},
                    }
                  }
                ]
              },
            }
          }
        });
      });
      final art = await ArtFinder.find(_r('The moon, the moon.'), Random(2));
      expect(art!.title, 'Moonrise');
      expect(art.artist, 'Caspar David Friedrich');
      expect(art.credit, startsWith('Wikimedia Commons'));
    });

    test('a saved picture is named by its title, artist and date', () {
      const a = Artwork(imageUrl: 'u', title: 'The Concourse: of Birds?', artist: 'Habiballah of Sava', date: 'ca. 1600', credit: 'c');
      expect(ArtSaver.fileName(a), 'The Concourse of Birds — Habiballah of Sava (ca. 1600)');
    });
  });

  group('pictures in the library', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      Net.client = MockClient((req) async => http.Response('offline', 503));
    });

    test('a reading gets its picture after it arrives, and keeps it across restarts', () async {
      final lib = await Library.load();
      lib.findArt = (r, rng) async => const Artwork(imageUrl: 'https://img/a.jpg', title: 'A', credit: 'The Met');
      final r = _r('words');
      lib.tonight.readings[ReadingType.poem] = r;
      await lib.ensureTonight(); // fills the other two (they fail offline) and attaches art to the poem
      await pumpEventQueue();
      expect(lib.tonight.readings[ReadingType.poem]!.art!.title, 'A');
      final again = await Library.load();
      expect(again.tonight.readings[ReadingType.poem]!.art!.imageUrl, 'https://img/a.jpg');
    });

    test('Substack readings keep their own cover; switching art off stops the search', () async {
      final lib = await Library.load();
      var asked = 0;
      lib.findArt = (r, rng) async {
        asked++;
        return null;
      };
      lib.tonight.readings[ReadingType.essay] = _r('x', sourceId: 'substack');
      await lib.ensureTonight();
      await pumpEventQueue();
      expect(asked, 0); // the Substack essay has its own cover; the others failed to load
      await lib.setArtOn(false);
      final before = asked;
      lib.tonight.readings[ReadingType.poem] = _r('y', title: 'other');
      await lib.ensureTonight();
      await pumpEventQueue();
      expect(asked, before);
    });

    test('liked pictures are remembered', () async {
      final lib = await Library.load();
      const a = Artwork(imageUrl: 'https://img/a.jpg', title: 'A', credit: 'c');
      await lib.toggleArtLike(a);
      expect((await Library.load()).isArtLiked(a), isTrue);
      await lib.toggleArtLike(a);
      expect((await Library.load()).likedArt, isEmpty);
    });
  });

  group('adding a source by link', () {
    const rss = '<?xml version="1.0"?><rss><channel><title>Blog</title><language>fr</language>'
        '<item><title>Un</title><link>https://blog.example/un</link><description>Bonjour</description></item>'
        '</channel></rss>';

    test('a page that names its feed', () async {
      Net.client = MockClient((req) async => switch (req.url.path) {
            '/' => http.Response('<html><head><link rel="alternate" type="application/rss+xml" href="/flux.xml">'
                '</head><body></body></html>', 200),
            '/flux.xml' => http.Response(rss, 200),
            _ => http.Response('no', 404),
          });
      final found = await FeedSource.discover('https://blog.example/');
      expect(found.url, 'https://blog.example/flux.xml');
      expect(found.site, isFalse);
      expect(found.lang, 'fr');
    });

    test('a site with its feed at a usual address', () async {
      Net.client = MockClient((req) async => switch (req.url.path) {
            '/feed' => http.Response(rss, 200),
            _ => http.Response('<html><body>Home</body></html>', 200),
          });
      expect((await FeedSource.discover('https://blog.example/home')).url, 'https://blog.example/feed');
    });

    test('a site without a feed is read through its article links', () async {
      final article = '<html><head><title>Ein langer Text</title></head><body><article>'
          '${List.filled(10, '<p>${'Der Wald ist still und die Nacht ist lang, und wir gehen nach Hause. ' * 6}</p>').join()}'
          '</article></body></html>';
      Net.client = MockClient((req) async {
        final p = req.url.path;
        if (p == '/') {
          return http.Response.bytes(
              utf8.encode('<html lang="de"><head><title>Magazin</title></head><body>'
                  '<a href="/about">About</a><a href="/tag/x">Tag</a>'
                  '<a href="/2024/ein-langer-text">Ein langer Text über den Wald</a>'
                  '<a href="/2024/zweiter-text">Zweiter Text über die Nacht</a>'
                  '<a href="/2024/dritter-text">Dritter Text</a>'
                  '<a href="https://elsewhere.example/a-b-c">Elsewhere</a></body></html>'),
              200);
        }
        if (p.startsWith('/2024/')) return http.Response.bytes(utf8.encode(article), 200);
        return http.Response('no', 404);
      });
      final found = await FeedSource.discover('https://mag.example/');
      expect(found.site, isTrue);
      expect(found.title, 'Magazin');
      expect(found.lang, 'de');
      final src = FeedSource(id: 's', name: 'Magazin', type: ReadingType.essay, url: found.url, site: true, language: 'de');
      final r = await src.fetchFor(ReadingType.essay, Random(1));
      expect(r.url, startsWith('https://mag.example/2024/'));
      expect(r.lang, 'de');
      expect(FeedSource.fromJson(src.toJson()).site, isTrue);
    });
  });

  test('themes: dark is the default, old settings carry over', () {
    expect(AppTheme.fromName(null), AppTheme.dark);
    expect(AppTheme.fromName('light'), AppTheme.white);
    expect(AppTheme.fromName('midnight'), AppTheme.midnight);
    expect(AppTheme.dark.data.scaffoldBackgroundColor, const Color(0xFF000000));
    expect(AppTheme.dark.data.colorScheme.primary, lampColor);
    for (final t in AppTheme.values) {
      expect(t.data.colorScheme.brightness, t.palette.brightness);
    }
  });
}
