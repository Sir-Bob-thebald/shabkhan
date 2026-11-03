import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightly_reader/models/languages.dart';
import 'package:nightly_reader/models/reading.dart';
import 'package:nightly_reader/services/library.dart';
import 'package:nightly_reader/services/net.dart';
import 'package:nightly_reader/services/translator.dart';
import 'package:nightly_reader/sources/feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _rss(String lang, String text, {bool declare = true}) => '<?xml version="1.0"?><rss><channel><title>$lang feed</title>'
    '${declare ? '<language>$lang-XX</language>' : ''}'
    '<item><title>Item</title><link>https://$lang.example/1</link>'
    '<description><![CDATA[${List.filled(8, '<p>${text * 6}</p>').join()}]]></description></item>'
    '</channel></rss>';

const _ru = 'Он не знал, что делать, и долго смотрел в окно на пустую улицу. ';
const _de = 'Er wusste nicht, was er tun sollte, und sah lange aus dem Fenster auf die Straße. ';
const _fr = 'Il ne savait pas quoi faire et il regardait longtemps par la fenêtre dans la rue. ';

void main() {
  group('detecting languages', () {
    final samples = {
      'fa': 'گویند رها کنش که یاری بدخوست، خوبیش نیرزد به درشتی که دروست',
      'ar': 'كان الرجل يمشي في الطريق عندما رأى الكلب الصغير في الحديقة',
      'ru': _ru,
      'uk': 'Він не знав, що робити, і довго дивився у вікно на порожню вулицю. Її їжак.',
      'de': _de,
      'fr': _fr,
      'es': 'No sabía qué hacer y miró por la ventana durante mucho tiempo, pero la calle estaba vacía.',
      'it': 'Non sapeva che cosa fare e per molto tempo guardò dalla finestra della casa, ma la strada era vuota.',
      'en': 'The fog comes on little cat feet. It sits looking over harbor and city and then moves on.',
      'ja': '吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。',
      'zh': '床前明月光，疑是地上霜。举头望明月，低头思故乡。',
      'el': 'Η ζωή είναι ωραία όταν διαβάζεις ένα καλό βιβλίο το βράδυ.',
    };
    for (final e in samples.entries) {
      test(languageOf(e.key).name, () => expect(detectLanguage(e.value), e.key));
    }

    test('language tags are normalised', () {
      expect(normalizeLang('en-US'), 'en');
      expect(normalizeLang('ru_RU'), 'ru');
      expect(normalizeLang('FR'), 'fr');
      expect(normalizeLang('not a tag'), isNull);
      expect(isRtlLang('ar'), isTrue);
      expect(isRtlLang('ru'), isFalse);
    });
  });

  group('language preferences', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      Net.client = MockClient((req) async => http.Response.bytes(
          utf8.encode(switch (req.url.host) {
            'ru.example' => _rss('ru', _ru),
            'de.example' => _rss('de', _de),
            'fr.example' => _rss('fr', _fr),
            _ => _rss('xx', _de, declare: false),
          }),
          200));
    });

    Future<Library> polyglot() async {
      final lib = await Library.load();
      for (final c in ['ru', 'de', 'fr']) {
        final probe = await FeedSource.probe('https://$c.example/feed');
        expect(probe.lang, c); // from <language>
        await lib.addFeed(name: probe.title, url: 'https://$c.example/feed', type: ReadingType.story, lang: probe.lang);
      }
      return lib;
    }

    test('languages come from the sources, each starting equal', () async {
      final lib = await polyglot();
      expect(lib.languages.toSet(), {'fa', 'en', 'ru', 'de', 'fr'});
      expect(lib.langShare('ru'), closeTo(0.2, 1e-9));
    });

    test('Russian 50, German 25, French 25 gives half the stories in Russian', () async {
      final lib = await polyglot();
      await lib.setLangWeight('fa', 0);
      await lib.setLangWeight('en', 0);
      await lib.setLangWeight('ru', 50);
      await lib.setLangWeight('de', 25);
      await lib.setLangWeight('fr', 25);
      expect(lib.langShare('ru', ReadingType.story), closeTo(0.5, 1e-9));
      expect(lib.langShare('de', ReadingType.story), closeTo(0.25, 1e-9));

      final rng = Random(3);
      final firsts = <String, int>{};
      const runs = 4000;
      for (var i = 0; i < runs; i++) {
        final (_, lang) = lib.attemptOrder(ReadingType.story, rng).first;
        firsts[lang!] = (firsts[lang] ?? 0) + 1;
      }
      expect(firsts.keys.toSet(), {'ru', 'de', 'fr'}); // 0 means never first
      expect(firsts['ru']! / runs, closeTo(0.5, 0.03));
      expect(firsts['de']! / runs, closeTo(0.25, 0.03));

      // Tonight's story really comes from the chosen language's feed.
      await lib.ensureTonight();
      expect(['ru', 'de', 'fr'], contains(lib.tonight.readings[ReadingType.story]!.lang));
    });

    test('languages set to 0 are never used', () async {
      final lib = await polyglot();
      for (final c in lib.languages) {
        await lib.setLangWeight(c, 0);
      }
      expect(lib.attemptOrder(ReadingType.story, Random(1)), isEmpty);
      await lib.setLangWeight('de', 10);
      expect(lib.attemptOrder(ReadingType.story, Random(1)).map((a) => a.$2).toSet(), {'de'});
    });

    test('a feed with no declared language learns it from its first reading', () async {
      final lib = await Library.load();
      for (final s in lib.sources) {
        await lib.setEnabled(s, false);
      }
      await lib.addFeed(name: 'Mystery', url: 'https://mystery.example/feed', type: ReadingType.essay);
      final feed = lib.sources.last as FeedSource;
      expect(feed.language, isNull);
      expect(lib.attemptOrder(ReadingType.essay, Random(1)).single.$2, isNull);
      await lib.ensureTonight();
      expect((lib.sources.last as FeedSource).language, 'de');
      expect((await Library.load()).languages, ['de']);
    });
  });

  group('translation', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
    });

    test('long texts are cut at paragraph and sentence breaks, never mid-way', () {
      final paras = List.generate(30, (i) => 'Paragraph $i. ${'A sentence here. ' * 20}');
      final text = paras.join('\n\n');
      final chunks = Translator.chunks(text, 1000);
      expect(chunks.every((c) => c.length <= 1000), isTrue);
      expect(chunks.join('\n\n').replaceAll(RegExp(r'\s+'), ' '), text.replaceAll(RegExp(r'\s+'), ' '));
      expect(Translator.chunks('a\nb\nc', 480), ['a\nb\nc']); // poems keep their lines
    });

    test('Google is asked chunk by chunk and the translation is kept', () async {
      final asked = <String>[];
      Net.client = MockClient((req) async {
        expect(req.url.host, 'translate.googleapis.com');
        expect(req.url.queryParameters, containsPair('tl', 'en'));
        final q = Uri.splitQueryString(req.body)['q']!;
        asked.add(q);
        return http.Response.bytes(utf8.encode(jsonEncode([
          [
            ['EN(${q.length})', q, null]
          ],
          null,
          'ru',
        ])), 200);
      });
      final lib = await Library.load();
      final r = Reading(
        type: ReadingType.story,
        title: 'Окно',
        body: List.filled(20, _ru * 5).join('\n\n'),
        sourceId: 'f',
        sourceName: 'F',
        url: 'https://ru.example/1',
        lang: 'ru',
      );
      final t = await lib.translate(r, 'en');
      expect(t.title, startsWith('EN('));
      expect(asked.length, greaterThan(2)); // title + several body chunks
      expect('\n\n'.allMatches(t.body).length, asked.length - 2);
      final calls = asked.length;
      await lib.translate(r, 'en');
      expect(asked.length, calls); // cached
      expect((await Library.load()).cachedTranslation(r, 'en'), isNotNull);
    });

    test('MyMemory says when its daily quota is used up', () async {
      Net.client = MockClient((req) async => http.Response(
          jsonEncode({'responseStatus': 429, 'responseDetails': 'YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY'}),
          200));
      await expectLater(
          const Translator(TranslatorKind.myMemory).translate('Привет', from: 'ru', to: 'en'),
          throwsA(isA<SourceException>().having((e) => e.message, 'message', contains('FREE TRANSLATIONS'))));
    });

    test('settings and per-source auto-translation are remembered', () async {
      final lib = await Library.load();
      await lib.setTranslation(kind: TranslatorKind.libre, to: 'fa', libreUrl: ' https://lt.example ');
      await lib.setAutoTranslate(lib.sources.first, 'en');
      final reloaded = await Library.load();
      expect(reloaded.translatorKind, TranslatorKind.libre);
      expect(reloaded.translateTo, 'fa');
      expect(reloaded.libreUrl, 'https://lt.example');
      expect(reloaded.autoTranslate(reloaded.sources.first.id), 'en');
    });
  });
}
