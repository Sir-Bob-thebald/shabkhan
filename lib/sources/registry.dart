import '../models/reading.dart';
import 'english.dart';
import 'feed.dart';
import 'ganjoor.dart';
import 'source.dart';

/// A ready-made source the user can add from "Browse sources".
class CatalogEntry {
  final ReadingSource source;

  /// Part of a fresh install's list. Everything else waits in the catalog,
  /// so the Sources tab stays short.
  final bool starter;

  /// 'fa' or 'en', for grouping in the catalog.
  final String lang;

  const CatalogEntry(this.source, {this.starter = false, this.lang = 'en'});

  String get id => source.id;
}

CatalogEntry _fa(ReadingSource s, {bool starter = false}) => CatalogEntry(s, starter: starter, lang: 'fa');

FeedSource _feed(String id, String name, String blurb, String url, ReadingType? type, {String lang = 'en'}) =>
    FeedSource(id: 'cat-$id', name: name, type: type, url: url, blurb: blurb, language: lang);

/// A feed sorted by content that only offers [only].
FeedSource _mixed(String id, String name, String blurb, String url, Set<ReadingType> only) =>
    FeedSource(id: 'cat-$id', name: name, type: null, url: url, blurb: blurb, only: only, language: 'en');

GanjoorPoemSource _poet(String id, String name, String blurb, int poetId) =>
    GanjoorPoemSource(id: 'ganjoor-$id', name: name, description: blurb, poetId: poetId);

WikisourceStorySource _ws(String wiki, String id, String name, String blurb, ReadingType type, String category,
        {int minChars = 1500}) =>
    WikisourceStorySource(
        id: 'wikisource-$id', name: name, description: blurb, type: type, category: category, wiki: wiki, minChars: minChars);

/// Every ready-made source. Ids are stable: they key the on/off switches,
/// the weights and the user's list of added sources.
List<CatalogEntry> catalog() => [
      // Persian stories
      _fa(starter: true, GanjoorCategorySource(
        id: 'ganjoor-golestan',
        name: 'Golestan · گلستان سعدی',
        description: 'Tales from Saadi\'s Golestan (chapters 1–7)',
        type: ReadingType.story,
        categoryIds: [1666, 1667, 1668, 1669, 1670, 1671, 1672],
      )),
      _fa(starter: true, GanjoorCategorySource(
        id: 'ganjoor-kelile',
        name: 'Kelileh va Demneh · کلیله و دمنه',
        description: 'Animal fables translated by Nasrollah Monshi',
        type: ReadingType.story,
        categoryIds: [1695, 1697, 1698, 1699, 1700, 1701, 1702, 1703, 1704, 1705, 1707, 1708],
        minChars: 800,
      )),
      _fa(GanjoorCategorySource(
        id: 'ganjoor-baharestan',
        name: 'Baharestan · بهارستان جامی',
        description: 'Jami\'s short tales: sages, kings, lovers, jokes and animals',
        type: ReadingType.story,
        categoryIds: [2185, 2186, 2187, 2188, 2189, 2190, 2192],
        minChars: 400,
      )),
      _fa(GanjoorCategorySource(
        id: 'ganjoor-chaharmaqala',
        name: 'Chahar Maqala · چهار مقاله',
        description: 'Nezami Aruzi\'s anecdotes of scribes, poets, astrologers and physicians',
        type: ReadingType.story,
        categoryIds: [2228, 2229, 2230, 2231],
        minChars: 800,
      )),
      _fa(GanjoorCategorySource(
        id: 'ganjoor-tazkirat',
        name: 'Tazkirat al-Awliya · تذکرة الاولیا',
        description: 'Attar\'s lives and sayings of the Sufi saints',
        type: ReadingType.story,
        categoryIds: [1820],
        minChars: 1000,
        maxChars: 20000,
      )),
      // English stories
      CatalogEntry(starter: true, WikisourceStorySource()),
      CatalogEntry(_feed('everydayfiction', 'Every Day Fiction', 'A new piece of flash fiction every day',
          'https://everydayfiction.com/feed/', ReadingType.story)),
      CatalogEntry(_mixed('smokelong', 'SmokeLong Quarterly', 'Flash fiction under 1,000 words',
          'https://smokelong.com/feed/', {ReadingType.story})),
      CatalogEntry(_feed('clarkesworld', 'Clarkesworld', 'Science fiction and fantasy short stories',
          'https://clarkesworldmagazine.com/feed/', ReadingType.story)),
      CatalogEntry(_mixed('strangehorizons', 'Strange Horizons', 'Speculative fiction and poetry, sorted by content',
          'https://strangehorizons.com/feed/', {ReadingType.story, ReadingType.poem})),
      // Persian poems
      _fa(starter: true, GanjoorPoemSource()),
      _fa(_poet('hafez', 'Hafez · حافظ', 'Ghazals from the Divan of Hafez', 2)),
      _fa(_poet('saadi', 'Saadi · سعدی', 'Ghazals, Bustan and more from Saadi', 7)),
      _fa(_poet('moulavi', 'Rumi · مولوی', 'Divan-e Shams and the Masnavi', 5)),
      _fa(_poet('khayyam', 'Khayyam · خیام', 'The rubaiyat of Omar Khayyam', 3)),
      _fa(_poet('babataher', 'Baba Taher · باباطاهر', 'Dobeytis (quatrains) in the Lori dialect', 28)),
      _fa(_poet('parvin', 'Parvin Etesami · پروین اعتصامی', 'Debates, fables and qasidas', 8)),
      _fa(_poet('shahriar', 'Shahriar · شهریار', 'Twentieth-century ghazals', 35)),
      _fa(_poet('rahi', 'Rahi Moayyeri · رهی معیری', 'Twentieth-century lyric ghazals', 41)),
      // English poems
      CatalogEntry(starter: true, PoetryDbSource()),
      CatalogEntry(WikisourceStorySource(
        id: 'wikisource-poems',
        name: 'Wikisource poems',
        description: 'Public-domain English poems from Wikisource',
        type: ReadingType.poem,
        category: 'Poems',
        minChars: 200,
      )),
      // Persian essays
      _fa(starter: true, GanjoorCategorySource(
        id: 'ganjoor-qabus',
        name: 'Qabus-nameh · قابوس‌نامه',
        description: 'A father\'s chapters of advice to his son (11th century)',
        type: ReadingType.essay,
        categoryIds: [2220],
        minChars: 1000,
      )),
      _fa(starter: true, GanjoorCategorySource(
        id: 'ganjoor-obeyd',
        name: 'Akhlaq al-Ashraf · اخلاق‌الاشراف',
        description: 'Obeyd Zakani\'s satirical essay on the morals of the nobility',
        type: ReadingType.essay,
        categoryIds: [2156],
      )),
      _fa(_feed('tarjomaan', 'Tarjomaan · ترجمان', 'Essays in the humanities, translated into Persian',
          'https://tarjomaan.com/feed/', ReadingType.essay, lang: 'fa')),
      // English essays
      CatalogEntry(starter: true, LessWrongSource()),
      CatalogEntry(starter: true, PaulGrahamSource()),
      CatalogEntry(_feed('psyche', 'Psyche', 'Essays and guides on living well (Aeon\'s sister magazine)',
          'https://psyche.co/feed.rss', ReadingType.essay)),
      CatalogEntry(_feed('aeon', 'Aeon', 'Long essays on philosophy, science and culture',
          'https://aeon.co/feed.rss', ReadingType.essay)),
      CatalogEntry(_feed('marginalian', 'The Marginalian', 'Maria Popova on books, art and meaning',
          'https://www.themarginalian.org/feed/', ReadingType.essay)),
      CatalogEntry(_feed('nautilus', 'Nautilus', 'Science essays for the curious',
          'https://nautil.us/feed/', ReadingType.essay)),
      CatalogEntry(_feed('quanta', 'Quanta Magazine', 'Mathematics, physics, biology and computer science',
          'https://www.quantamagazine.org/feed/', ReadingType.essay)),
      // German (Wikisource)
      CatalogEntry(lang: 'de', _ws('de', 'de-maerchen', 'Märchen · Wikisource', 'Fairy tales: Grimm, Bechstein, Hauff…',
          ReadingType.story, 'Märchen', minChars: 1000)),
      CatalogEntry(lang: 'de', _ws('de', 'de-erzaehlung', 'Erzählungen · Wikisource', 'Classic German short prose',
          ReadingType.story, 'Erzählung')),
      CatalogEntry(lang: 'de', _ws('de', 'de-gedicht', 'Gedichte · Wikisource', 'German poems: Goethe, Heine, Rilke…',
          ReadingType.poem, 'Gedicht', minChars: 200)),
      CatalogEntry(lang: 'de', _ws('de', 'de-essay', 'Essays · Wikisource', 'German essays and short treatises',
          ReadingType.essay, 'Essay')),
      // French (Wikisource)
      CatalogEntry(lang: 'fr', _ws('fr', 'fr-nouvelles', 'Nouvelles · Wikisource', 'Short stories: Maupassant, Mérimée…',
          ReadingType.story, 'Nouvelles')),
      CatalogEntry(lang: 'fr', _ws('fr', 'fr-contes', 'Contes · Wikisource', 'Tales: Perrault, Voltaire, Daudet…',
          ReadingType.story, 'Contes', minChars: 1000)),
      CatalogEntry(lang: 'fr', _ws('fr', 'fr-poesie', 'Poésie · Wikisource', 'French poems: Hugo, Baudelaire, Verlaine…',
          ReadingType.poem, 'Poésie', minChars: 200)),
      CatalogEntry(lang: 'fr', _ws('fr', 'fr-essais', 'Essais · Wikisource', 'Essays: Montaigne and others',
          ReadingType.essay, 'Essais')),
    ];

/// The sources a fresh install starts with.
List<ReadingSource> builtInSources() => [for (final e in catalog()) if (e.starter) e.source];
