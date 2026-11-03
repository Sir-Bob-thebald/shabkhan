import 'dart:math';

import '../models/artwork.dart';
import '../models/reading.dart';
import 'net.dart';

/// What the art search looks for, in order of importance: what the text is
/// about, where it comes from, and when.
class ArtHints {
  final String subject;
  final String? place;
  final ({int from, int to})? era;
  const ArtHints(this.subject, this.place, this.era);

  @override
  String toString() => '$subject / ${place ?? '-'} / ${era == null ? '-' : '${era!.from}–${era!.to}'}';
}

/// Picture subjects and the words (in several languages) that suggest them.
const _motifs = <String, List<String>>{
  'moon': ['moon', 'lunar', 'مهتاب', 'ماه', 'mond', 'lune', 'луна', 'луны', 'luna', 'قمر'],
  'night': ['night', 'شب', 'nacht', 'nuit', 'ночь', 'ночи', 'noche', 'notte', 'ليل'],
  'garden': ['garden', 'باغ', 'گلستان', 'بوستان', 'garten', 'jardin', 'сад', 'jardín', 'giardino', 'حديقة'],
  'rose': ['rose', 'roses', 'گل', 'گلی', 'роза', 'rosa'],
  'wine': ['wine', 'باده', 'شراب', 'ساقی', 'wein', 'vin', 'вино', 'vino'],
  'king': ['king', 'sultan', 'شاه', 'پادشاه', 'سلطان', 'ملک', 'könig', 'roi', 'царь', 'король', 'rey', 'ملك'],
  'lion': ['lion', 'löwe', 'лев', 'león', 'leone', 'أسد'],
  'fox': ['fox', 'روباه', 'fuchs', 'renard', 'лиса', 'zorro', 'volpe'],
  'bird': ['bird', 'birds', 'مرغ', 'پرنده', 'بلبل', 'vogel', 'oiseau', 'птица', 'pájaro', 'uccello', 'طائر'],
  'sea': ['sea', 'ocean', 'دریا', 'meer', 'mer', 'море', 'mar', 'mare', 'بحر'],
  'river': ['river', 'رود', 'fluss', 'rivière', 'fleuve', 'река', 'río', 'fiume', 'نهر'],
  'mountain': ['mountain', 'mountains', 'کوه', 'berg', 'montagne', 'гора', 'горы', 'montaña', 'montagna', 'جبل'],
  'tree': ['tree', 'trees', 'درخت', 'baum', 'arbre', 'дерево', 'árbol', 'albero', 'شجرة'],
  'horse': ['horse', 'اسب', 'pferd', 'cheval', 'лошадь', 'конь', 'caballo', 'cavallo', 'حصان'],
  'ship': ['ship', 'boat', 'کشتی', 'schiff', 'navire', 'bateau', 'корабль', 'лодка', 'barco', 'nave'],
  'battle': ['war', 'battle', 'جنگ', 'نبرد', 'krieg', 'guerre', 'война', 'guerra', 'حرب'],
  'lovers': ['love', 'lover', 'عشق', 'عاشق', 'معشوق', 'یار', 'liebe', 'amour', 'любовь', 'amor', 'amore', 'حب'],
  'death': ['death', 'grave', 'مرگ', 'گور', 'tod', 'mort', 'смерть', 'muerte', 'morte', 'موت'],
  'woman': ['woman', 'mother', 'زن', 'مادر', 'frau', 'mutter', 'femme', 'mère', 'женщина', 'мать', 'mujer', 'donna'],
  'child': ['child', 'children', 'کودک', 'فرزند', 'kind', 'enfant', 'ребёнок', 'дети', 'niño', 'bambino'],
  'city': ['city', 'street', 'شهر', 'stadt', 'ville', 'город', 'ciudad', 'città', 'مدينة'],
  'winter': ['winter', 'snow', 'زمستان', 'برف', 'schnee', 'hiver', 'neige', 'зима', 'снег', 'invierno', 'inverno'],
  'spring': ['spring', 'بهار', 'frühling', 'printemps', 'весна', 'primavera'],
  'sun': ['sun', 'sunrise', 'خورشید', 'آفتاب', 'sonne', 'soleil', 'солнце', 'sol', 'sole', 'شمس'],
  'prayer': ['prayer', 'god', 'saint', 'dervish', 'نماز', 'دعا', 'درویش', 'صوفی', 'خدا', 'gebet', 'gott', 'prière', 'dieu', 'молитва', 'бог'],
  'scholar': ['book', 'scholar', 'teacher', 'کتاب', 'حکیم', 'دانا', 'استاد', 'buch', 'livre', 'книга', 'libro'],
  'music': ['music', 'song', 'musician', 'نی', 'چنگ', 'رباب', 'musik', 'musique', 'музыка', 'música', 'musica'],
  'hunt': ['hunt', 'hunter', 'شکار', 'jagd', 'chasse', 'охота', 'caza', 'caccia'],
  'forest': ['forest', 'woods', 'جنگل', 'wald', 'forêt', 'лес', 'bosque', 'bosco'],
};

/// Where a language's literature comes from, as The Met names places.
const _places = {
  'fa': 'Iran', 'ar': 'Egypt', 'ur': 'India', 'hi': 'India', 'tr': 'Turkey', 'en': 'England', //
  'de': 'Germany', 'fr': 'France', 'ru': 'Russia', 'uk': 'Ukraine', 'es': 'Spain', 'it': 'Italy',
  'pt': 'Portugal', 'nl': 'Netherlands', 'sv': 'Sweden', 'pl': 'Poland', 'el': 'Greece', 'he': 'Israel',
  'ja': 'Japan', 'zh': 'China', 'ko': 'Korea', 'hy': 'Armenia', 'ka': 'Georgia',
};

/// When a source's (or author's) texts were written, matched against the
/// source id and the author.
const _eras = <(List<String>, int, int)>[
  (['golestan', 'saadi', 'سعدی'], 1250, 1450),
  (['hafez', 'حافظ'], 1350, 1550),
  (['moulavi', 'مولانا', 'مولوی'], 1250, 1450),
  (['khayyam', 'خیام'], 1100, 1300),
  (['kelile', 'منشی'], 1150, 1400),
  (['baharestan', 'جامی'], 1450, 1600),
  (['tazkirat', 'عطار'], 1200, 1400),
  (['chaharmaqala', 'عروضی'], 1100, 1300),
  (['qabus', 'عنصرالمعالی'], 1050, 1200),
  (['obeyd', 'عبید'], 1300, 1450),
  (['babataher', 'باباطاهر'], 1000, 1150),
  (['parvin', 'shahriar', 'rahi', 'پروین', 'شهریار', 'رهی'], 1880, 1960),
  (['wikisource'], 1780, 1920),
  (['poetrydb'], 1600, 1900),
];

typedef _Collection = Future<Artwork?> Function(Random rng, {required String q, String? place, ({int from, int to})? era});

/// Finds a public-domain work of art to go with a reading, from four open
/// collections (The Met, Cleveland, SMK, Europeana) in a random order, then
/// Wikimedia Commons. Every search keeps the subject; place, then era, are
/// dropped only when no collection has a match.
class ArtFinder {
  static const _met = 'https://collectionapi.metmuseum.org/public/collection';

  static ArtHints hintsFor(Reading r) {
    final words = '${r.title} ${r.body.length > 6000 ? r.body.substring(0, 6000) : r.body}'
        .toLowerCase()
        .split(RegExp(r'[^\p{L}]+', unicode: true))
        .where((w) => w.isNotEmpty)
        .toList();
    String? best;
    var bestCount = 0;
    for (final e in _motifs.entries) {
      var n = 0;
      for (final w in words) {
        for (final k in e.value) {
          // Persian and Arabic words take suffixes (ها، ی، ش…); allow them on longer stems.
          if (w == k || (k.length >= 3 && w.startsWith(k) && w.length <= k.length + 2)) n++;
        }
      }
      if (n > bestCount) (best, bestCount) = (e.key, n);
    }
    final subject = best ??
        switch (r.type) {
          ReadingType.story => 'figures',
          ReadingType.poem => 'landscape',
          ReadingType.essay => 'portrait',
        };
    final id = '${r.sourceId} ${r.author ?? ''}'.toLowerCase();
    final era = _eras.where((e) => e.$1.any(id.contains)).map((e) => (from: e.$2, to: e.$3)).firstOrNull;
    return ArtHints(subject, _places[r.lang], era);
  }

  /// A work for [r], or null when none was found (or the network is down).
  static Future<Artwork?> find(Reading r, Random rng) async {
    final h = hintsFor(r);
    final tries = <(String?, ({int from, int to})?)>[
      (h.place, h.era),
      (h.place, null),
      (null, h.era),
      (null, null),
    ];
    // Every collection is asked at each step, in a random order per reading,
    // so the pictures come from many museums; a step is only relaxed when none
    // of them has a match.
    final collections = [..._collections]..shuffle(rng);
    for (final (place, era) in tries) {
      if (place == null && era == null && h.place != null) {
        // Last resort before dropping everything: the place alone, any subject.
        for (final c in collections) {
          final art = await c(rng, q: 'painting', place: h.place, era: h.era);
          if (art != null) return art;
        }
      }
      for (final c in collections) {
        final art = await c(rng, q: h.subject, place: place, era: era);
        if (art != null) return art;
      }
    }
    return _fromCommons(rng, '${h.subject} painting');
  }

  /// Open-access collections with a search API, all public domain or CC0.
  static const _collections = <_Collection>[_fromMet, _fromCleveland, _fromSmk, _fromEuropeana];

  /// How collections that search by keyword name a place.
  static const _placeWords = {
    'Iran': 'Persian', 'Egypt': 'Egyptian', 'India': 'Indian', 'Turkey': 'Ottoman', 'England': 'British', //
    'Germany': 'German', 'France': 'French', 'Russia': 'Russian', 'Ukraine': 'Ukrainian', 'Spain': 'Spanish',
    'Italy': 'Italian', 'Portugal': 'Portuguese', 'Netherlands': 'Dutch', 'Sweden': 'Swedish', 'Poland': 'Polish',
    'Greece': 'Greek', 'Israel': 'Hebrew', 'Japan': 'Japanese', 'China': 'Chinese', 'Korea': 'Korean',
    'Armenia': 'Armenian', 'Georgia': 'Georgian',
  };

  static String _query(String q, String? place) => place == null ? q : '$q ${_placeWords[place] ?? place}';

  /// The Cleveland Museum of Art: everything with an image here is CC0.
  static Future<Artwork?> _fromCleveland(Random rng, {required String q, String? place, ({int from, int to})? era}) async {
    final Map res;
    try {
      res = await Net.getJson(Uri.https('openaccess-api.clevelandart.org', '/api/artworks/', {
        'q': _query(q, place),
        'has_image': '1',
        'cc0': '1',
        'limit': '40',
        if (era != null) 'created_after': '${era.from}',
        if (era != null) 'created_before': '${era.to}',
      }).toString()) as Map;
    } on Exception {
      return null;
    }
    final items = [...(res['data'] as List? ?? const [])]..shuffle(rng);
    for (final a in items.cast<Map>()) {
      final images = (a['images'] as Map?) ?? const {};
      final web = (images['web'] as Map?)?['url'] as String?;
      if (web == null) continue;
      final creators = (a['creators'] as List? ?? const []).cast<Map>();
      return Artwork(
        imageUrl: web,
        fullUrl: (images['print'] as Map?)?['url'] as String? ?? web,
        title: a['title'] as String? ?? 'Untitled',
        artist: creators.isEmpty ? null : creators.first['description'] as String?,
        date: a['creation_date'] as String?,
        origin: (a['culture'] as List?)?.cast<String>().firstOrNull,
        credit: 'Cleveland Museum of Art · CC0',
        pageUrl: a['url'] as String?,
      );
    }
    return null;
  }

  /// SMK, the National Gallery of Denmark (public-domain works only). It can't
  /// filter by date here, so it sits out the steps that need an era.
  static Future<Artwork?> _fromSmk(Random rng, {required String q, String? place, ({int from, int to})? era}) async {
    if (era != null) return null;
    final Map res;
    try {
      res = await Net.getJson(Uri.https('api.smk.dk', '/api/v1/art/search/', {
        'keys': _query(q, place),
        'filters': '[has_image:true],[public_domain:true]',
        'offset': '0',
        'rows': '40',
      }).toString()) as Map;
    } on Exception {
      return null;
    }
    final items = [...(res['items'] as List? ?? const [])]..shuffle(rng);
    for (final a in items.cast<Map>()) {
      final thumb = a['image_thumbnail'] as String?;
      if (thumb == null || a['public_domain'] != true) continue;
      final titles = (a['titles'] as List? ?? const []).cast<Map>();
      final title = (titles.where((t) => t['language'] == 'engelsk').firstOrNull ?? titles.firstOrNull)?['title'];
      final made = (a['production'] as List? ?? const []).cast<Map>().firstOrNull;
      final when = (a['production_date'] as List? ?? const []).cast<Map>().firstOrNull;
      return Artwork(
        imageUrl: thumb,
        fullUrl: a['image_native'] as String? ?? thumb,
        title: title as String? ?? 'Untitled',
        artist: made?['creator'] as String?,
        date: when?['period'] as String?,
        credit: 'SMK, National Gallery of Denmark · Public domain',
        pageUrl: a['frontend_url'] as String?,
      );
    }
    return null;
  }

  /// Europeana, which gathers thousands of European museums. Only items marked
  /// public domain or CC0 are used. `api2demo` is Europeana's public demo key.
  static Future<Artwork?> _fromEuropeana(Random rng, {required String q, String? place, ({int from, int to})? era}) async {
    final Map res;
    try {
      final params = <String, dynamic>{
        'wskey': const String.fromEnvironment('EUROPEANA_KEY', defaultValue: 'api2demo'),
        'query': _query(q, place),
        'reusability': 'open',
        'media': 'true',
        'type': 'IMAGE',
        'rows': '40',
        if (era != null) 'qf': 'YEAR:[${era.from} TO ${era.to}]',
      };
      res = await Net.getJson(Uri.https('api.europeana.eu', '/record/v2/search.json', params).toString()) as Map;
    } on Exception {
      return null;
    }
    final items = [...(res['items'] as List? ?? const [])]..shuffle(rng);
    String? first(Map a, String k) => (a[k] as List?)?.cast<Object?>().whereType<String>().firstOrNull;
    for (final a in items.cast<Map>()) {
      final rights = first(a, 'rights') ?? '';
      if (!rights.contains('publicdomain') && !rights.contains('/zero/')) continue;
      final preview = first(a, 'edmPreview');
      if (preview == null) continue;
      return Artwork(
        // The preview service scales the image; the original can be huge.
        imageUrl: '$preview&size=w400',
        fullUrl: first(a, 'edmIsShownBy') ?? preview,
        title: first(a, 'title') ?? 'Untitled',
        artist: first(a, 'dcCreator'),
        date: first(a, 'year'),
        origin: first(a, 'country'),
        credit: '${first(a, 'dataProvider') ?? 'Europeana'} via Europeana · Public domain',
        pageUrl: (a['guid'] as String?)?.split('?').first,
      );
    }
    return null;
  }

  static Future<Artwork?> _fromMet(Random rng, {required String q, String? place, ({int from, int to})? era}) async {
    final params = {
      'q': q,
      'hasImages': 'true',
      'isPublicDomain': 'true',
      'limit': '60',
      'geoLocation': ?place,
      if (era != null) 'dateBegin': '${era.from}',
      if (era != null) 'dateEnd': '${era.to}',
    };
    final Map res;
    try {
      res = await Net.getJson(Uri.parse('$_met/v1.1/search').replace(queryParameters: params).toString()) as Map;
    } on Exception {
      return null;
    }
    final ids = [...(res['objectIDs'] as List? ?? const [])]..shuffle(rng);
    for (final id in ids.take(4)) {
      try {
        final o = await Net.getJson('$_met/v1/objects/$id') as Map;
        final small = o['primaryImageSmall'] as String? ?? '';
        if (o['isPublicDomain'] != true || small.isEmpty) continue;
        String? s(String k) => (o[k] as String?)?.trim().isEmpty ?? true ? null : (o[k] as String).trim();
        return Artwork(
          imageUrl: small,
          fullUrl: s('primaryImage'),
          title: s('title') ?? 'Untitled',
          artist: s('artistDisplayName'),
          date: s('objectDate'),
          origin: s('country') ?? s('culture'),
          credit: 'The Met · Public domain',
          pageUrl: s('objectURL'),
        );
      } on Exception {
        continue;
      }
    }
    return null;
  }

  static Future<Artwork?> _fromCommons(Random rng, String q) async {
    final Map res;
    try {
      res = await Net.getJson(Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'generator': 'search',
        'gsrnamespace': '6',
        'gsrsearch': '$q filetype:bitmap',
        'gsrlimit': '30',
        'gsroffset': '${rng.nextInt(5) * 30}',
        'prop': 'imageinfo',
        'iiprop': 'url|extmetadata',
        'iiurlwidth': '900',
        'iiextmetadatafilter': 'ObjectName|Artist|DateTimeOriginal|LicenseShortName',
      }).toString()) as Map;
    } on Exception {
      return null;
    }
    final pages = [...((res['query'] as Map?)?['pages'] as Map? ?? const {}).values]..shuffle(rng);
    String strip(String? html) => (html ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();
    for (final p in pages.cast<Map>()) {
      final info = ((p['imageinfo'] as List?)?.firstOrNull as Map?) ?? const {};
      final meta = (info['extmetadata'] as Map?) ?? const {};
      String? m(String k) => ((meta[k] as Map?)?['value'] as String?);
      final license = m('LicenseShortName') ?? '';
      // Public domain only, so a liked picture can be kept freely.
      if (!RegExp('public domain|cc0|pd', caseSensitive: false).hasMatch(license)) continue;
      final thumb = info['thumburl'] as String?;
      if (thumb == null) continue;
      final artist = strip(m('Artist'));
      return Artwork(
        imageUrl: thumb,
        fullUrl: info['url'] as String?,
        title: strip(m('ObjectName')).isEmpty ? (p['title'] as String).replaceFirst('File:', '') : strip(m('ObjectName')),
        artist: artist.isEmpty ? null : artist,
        date: strip(m('DateTimeOriginal')).isEmpty ? null : strip(m('DateTimeOriginal')),
        credit: 'Wikimedia Commons · $license',
        pageUrl: info['descriptionurl'] as String?,
      );
    }
    return null;
  }
}
