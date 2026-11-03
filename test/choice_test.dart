import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightly_reader/models/reading.dart';
import 'package:nightly_reader/services/library.dart';
import 'package:nightly_reader/sources/classify.dart';
import 'package:nightly_reader/sources/registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('sorting by content', () {
    test('short broken lines are a poem', () {
      const text = 'I wandered lonely as a cloud\nThat floats on high o\'er vales and hills,\n'
          'When all at once I saw a crowd,\nA host, of golden daffodils;\n\n'
          'Beside the lake, beneath the trees,\nFluttering and dancing in the breeze.';
      expect(classify(title: 'Daffodils', text: text), ReadingType.poem);
    });

    test('Persian verse is a poem', () {
      const text = 'گویند رها کنش که یاری بدخوست\nخوبیش نیرزد به درشتی که دروست\n\n'
          'گر خوی بدش بود چه باک است مرا\nمن آن نظر کنم که رویش نیکوست';
      expect(classify(text: text), ReadingType.poem);
    });

    test('dialogue and speech verbs are a story', () {
      final text = [
        for (var i = 0; i < 4; i++) ...[
          'The rain had not stopped for three days when Mara finally opened the door of the shop again and looked out.',
          '“Are you coming in?” she asked the boy standing under the awning.',
          '“Maybe,” he said, and did not move.',
        ],
      ].join('\n\n');
      expect(classify(title: 'The Shop', text: text), ReadingType.story);
    });

    test('argument in long paragraphs is an essay', () {
      final para = 'We tend to think that attention is a resource we spend, but it may be closer to a habit '
          'we build. The evidence for this is mixed, and the argument deserves care. ';
      final text = List.filled(8, para * 3).join('\n\n');
      expect(classify(title: 'On Attention', text: text), ReadingType.essay);
    });

    test('the author\'s own labels win over the shape of the text', () {
      final prose = List.filled(8, 'A long paragraph of plain prose about a quiet town. ' * 4).join('\n\n');
      expect(classify(tags: ['Fiction'], text: prose), ReadingType.story);
      expect(classify(section: 'Poetry', text: prose), ReadingType.poem);
      expect(classify(tags: ['داستان کوتاه'], text: prose), ReadingType.story);
    });
  });

  group('chances', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
    });

    test('every source starts with an equal chance, whatever its size', () async {
      final lib = await Library.load();
      final essays = lib.active(ReadingType.essay);
      expect(essays, isNotEmpty);
      for (final s in essays) {
        expect(lib.chance(s, ReadingType.essay), closeTo(1 / essays.length, 1e-9));
      }
    });

    test('weights shift the chances, survive a restart, and can be evened out', () async {
      final lib = await Library.load();
      final essays = lib.active(ReadingType.essay);
      final fav = essays.first;
      await lib.setWeight(fav, ReadingType.essay, 10);
      // Within its language: half the nights are in each of Persian and English.
      final sameLang = essays.where((s) => s.lang == fav.lang).length - 1;
      expect(lib.chance(fav, ReadingType.essay), closeTo(0.5 * 10 / (10 + sameLang * Library.defaultWeight), 1e-9));
      expect(lib.active(ReadingType.essay).fold<double>(0, (p, s) => p + lib.chance(s, ReadingType.essay)), closeTo(1, 1e-9));

      final reloaded = await Library.load();
      expect(reloaded.weight(reloaded.active(ReadingType.essay).first, ReadingType.essay), 10);
      await reloaded.evenOut(ReadingType.essay);
      expect(reloaded.weight(fav, ReadingType.essay), Library.defaultWeight);
    });

    test('a switched-off source has no chance and frees its share', () async {
      final lib = await Library.load();
      final poems = lib.active(ReadingType.poem);
      await lib.setEnabled(poems.first, false);
      expect(lib.chance(poems.first, ReadingType.poem), 0);
      expect(lib.chance(poems.last, ReadingType.poem), closeTo(1 / (poems.length - 1), 1e-9));
    });

    test('a heavier source comes first more often, in proportion to its weight', () async {
      final lib = await Library.load();
      // Two Persian poem sources, so the weight decides between them.
      await lib.addFromCatalog(lib.catalogEntries.firstWhere((e) => e.id == 'ganjoor-hafez'));
      final poems = lib.active(ReadingType.poem);
      for (final s in poems) {
        await lib.setWeight(s, ReadingType.poem, 1);
      }
      await lib.setWeight(poems.first, ReadingType.poem, 9);
      final rng = Random(7);
      var first = 0;
      const runs = 4000;
      for (var i = 0; i < runs; i++) {
        if (lib.attemptOrder(ReadingType.poem, rng).first.$1.id == poems.first.id) first++;
      }
      expect(first / runs, closeTo(lib.chance(poems.first, ReadingType.poem), 0.03));
    });
  });

  group('catalog', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
    });

    test('ids are unique, and a fresh install starts with only the starters', () async {
      final ids = catalog().map((e) => e.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      final lib = await Library.load();
      expect(lib.sources.map((s) => s.id).toSet(), catalog().where((e) => e.starter).map((e) => e.id).toSet());
    });

    test('adding and removing catalog sources is remembered', () async {
      final lib = await Library.load();
      final hafez = lib.catalogEntries.firstWhere((e) => e.id == 'ganjoor-hafez');
      await lib.addFromCatalog(hafez);
      expect((await Library.load()).sources.map((s) => s.id), contains('ganjoor-hafez'));
      final golestan = lib.sources.firstWhere((s) => s.id == 'ganjoor-golestan');
      await lib.setWeight(golestan, ReadingType.story, 9);
      await lib.removeFromList(golestan);
      final reloaded = await Library.load();
      expect(reloaded.sources.map((s) => s.id), isNot(contains('ganjoor-golestan')));
      // Added back later, it starts fresh.
      await reloaded.addFromCatalog(reloaded.catalogEntries.firstWhere((e) => e.id == 'ganjoor-golestan'));
      expect(reloaded.weight(golestan, ReadingType.story), Library.defaultWeight);
    });

    test('a feed sorted by content counts for every type', () async {
      final lib = await Library.load();
      await lib.addFeed(name: 'Mag', url: 'https://mag.example/feed', type: null);
      final feed = lib.sources.last;
      for (final t in ReadingType.values) {
        expect(lib.active(t), contains(feed));
      }
      final reloaded = await Library.load();
      expect(reloaded.sources.last.types, ReadingType.values.toSet());
    });
  });
}
