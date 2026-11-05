import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

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

/// How a subject is named in museum titles and tags, besides the words in
/// [_motifs]: English names, Danish ones for SMK (a `*` matches compounds such
/// as "måneskin"), and the subjects used when no motif is found.
const _titleWords = <String, List<String>>{
  'moon': ['moon', 'moonlight', 'moonlit', 'crescent', 'måne*'],
  'night': ['night', 'nocturne', 'evening', 'nat'],
  'garden': ['garden', 'gardens', 'haven'],
  'rose': ['rose', 'roser'],
  'wine': ['wine', 'cupbearer', 'drinking', 'vin'],
  'king': ['king', 'shah', 'sultan', 'prince', 'emperor', 'konge*'],
  'lion': ['lion', 'løve*'],
  'fox': ['fox', 'ræv*'],
  'bird': ['bird', 'nightingale', 'peacock', 'crane', 'simurgh', 'fugl*'],
  'sea': ['sea', 'ocean', 'coast', 'seascape', 'shore', 'hav', 'havet'],
  'river': ['river', 'stream', 'flod*'],
  'mountain': ['mountain', 'bjerg*'],
  'tree': ['tree', 'træ*'],
  'horse': ['horse', 'rider', 'horseman', 'hest*'],
  'ship': ['ship', 'boat', 'skib*'],
  'battle': ['battle', 'combat', 'slag', 'kamp'],
  'lovers': ['lovers', 'couple', 'elskende'],
  'death': ['death', 'grave', 'mourning', 'tomb', 'død'],
  'woman': ['woman', 'women', 'lady', 'kvinde*'],
  'child': ['children', 'boy', 'girl', 'barn'],
  'city': ['city', 'town', 'byen'],
  'winter': ['winter', 'snow', 'sne'],
  'spring': ['spring', 'blossom', 'forår*'],
  'sun': ['sun', 'sunrise', 'sunset'],
  'prayer': ['prayer', 'praying', 'saint', 'dervish', 'sufi', 'mosque', 'bøn'],
  'scholar': ['scholar', 'sage', 'philosopher', 'reading', 'poet', 'lærd*'],
  'music': ['music', 'musician', 'musicians', 'lute', 'flute', 'harp'],
  'hunt': ['hunt', 'hunting', 'hunter', 'jagt'],
  'forest': ['forest', 'woods', 'skov*'],
  'figures': ['figure', 'figures', 'people', 'scene'],
  'landscape': ['landscape', 'view', 'landskab*', 'landschaft', 'paysage'],
  'portrait': ['portrait', 'portræt*', 'bildnis', 'porträt'],
};

/// Motif words that mean something else in a museum title ("kind" is German
/// for child, "mar" the start of many names).
const _ambiguous = {'kind', 'mar', 'mare', 'god', 'sol', 'ماه', 'گل'};

/// One search result, with what the quality checks look at.
class _Found {
  final Artwork art;

  /// Title, tags and subject terms: the subject has to be named here.
  final String about;

  /// The collection's object type ("Paintings", "Print", "Maleri"…), if it gives one.
  final String? kind;
  final int? width, height;
  const _Found(this.art, {required this.about, this.kind, this.width, this.height});
}

typedef _Collection = Future<Artwork?> Function(Random rng, {required String q, String? place, ({int from, int to})? era});

/// Finds a public-domain work of art to go with a reading, from seven open
/// collections in a random order, then Wikimedia Commons. Every search keeps
/// the subject; place, then era, are dropped only when no collection has a
/// match. Every result has to pass [_fits]: a picture, textile, sculpture, photo, map or page (not a pot, coin or other object), with
/// the subject in its title or tags, of a shape that suits a card.
class ArtFinder {
  static const _met = 'https://collectionapi.metmuseum.org/public/collection';

  /// The last-resort query, which matches any subject.
  static const _anySubject = 'painting';

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
          final art = await c(rng, q: _anySubject, place: h.place, era: h.era);
          if (art != null) return art;
        }
      }
      for (final c in collections) {
        final art = await c(rng, q: h.subject, place: place, era: era);
        if (art != null) return art;
      }
    }
    return _fromCommons(rng, h.subject);
  }

  /// Open-access collections with a search API, all public domain or CC0.
  static final _collections = <_Collection>[
    _fromMet,
    _fromCleveland,
    _fromSmk,
    _fromEuropeana,
    _fromMia,
    _fromOpenverse('smithsonian_freer_gallery_of_art', 'Freer Gallery of Art, Smithsonian'),
    _fromOpenverse('smithsonian_american_art_museum', 'Smithsonian American Art Museum'),
  ];

  /// Each collection's pick for [subject], in order, for the live tests.
  @visibleForTesting
  static Future<List<Artwork?>> eachCollection(String subject, Random rng, {String? place, ({int from, int to})? era}) async =>
      [for (final c in _collections) await c(rng, q: subject, place: place, era: era)];

  // ---- What counts as a good picture ----

  /// Object types that show something, in the collections' own words (English,
  /// Danish, German, French, Dutch): pictures, and also textiles, sculpture,
  /// photographs, maps, fragments, and text or calligraphy pages.
  static final _pictureKind = RegExp(
      r'paint|drawing|print|codex|codices|manuscript|illuminat|miniature|folio|album|watercolo|gouache|woodcut|'
      r'woodblock|etching|engraving|lithograph|illustrat|pastel|fresco|maleri|tegning|radering|grafik|kobberstik|'
      r'træsnit|litografi|akvarel|gemälde|malerei|zeichnung|kupferstich|radierung|holzschnitt|aquarell|peinture|'
      r'dessin|estampe|gravure|schilderij|tekening|prent|'
      r'textile|fabric|tapestr|embroider|carpet|\brug|weav|\blace|tekstil|textil|'
      r'sculpt|statue|figurine|relief|carving|skulptur|beeldhouw|'
      r'photo|negative|stereo|albumen|daguerr|gelatin|fotografi|foto|'
      r'\bmaps?\b|chart\b|atlas|cartograph|landkarte|kaart|'
      r'calligraph|qur.?an|koran|document|fragment|book',
      caseSensitive: false);

  /// Object types that aren't wanted even when a picture is on them: pots and
  /// tableware, coins and seals, furniture, jewellery, arms, glass, tiles,
  /// clothing, bindings and reproductions.
  static final _notPicture = RegExp(
      r'ceramic|porcelain|pottery|stoneware|earthenware|vessel|bowl|vase|\bjar|flask|coin|medal|\bseal|furniture|'
      r'jewel|armou?r|weapon|sword|metalwork|glass|\btile|sherd|shard|costume|garment|clothing|binding|bookplate|'
      r'wallpaper|lacquer|reproduction',
      caseSensitive: false);

  /// Titles of objects that are refused whatever their type says.
  static final _notPictureTitle = RegExp(r'sherd|\bshard|\bcoins?\b|\bseals?\b|\bvase\b|\bbowl\b|\bjar\b', caseSensitive: false);

  static final _subjectRes = <String, RegExp?>{};

  /// The subject's names, as a whole word (plurals allowed), or null for
  /// [_anySubject].
  static RegExp? _subjectRe(String q) => _subjectRes.putIfAbsent(q, () {
        if (q == _anySubject) return null;
        final alts = _wordsFor(q)
            .map((w) => w.endsWith('*')
                ? '${RegExp.escape(w.substring(0, w.length - 1))}\\p{L}*'
                : '${RegExp.escape(w)}(?:s|es)?')
            .join('|');
        return RegExp('(?<!\\p{L})(?:$alts)(?!\\p{L})', caseSensitive: false, unicode: true);
      });

  static List<String> _wordsFor(String q) => {
        q,
        ...?_titleWords[q],
        ...?_motifs[q]?.where((w) => w.length >= 3 && !_ambiguous.contains(w)),
      }.toList();

  /// Not too long or too tall for a card (cropped to fill it), and not tiny.
  static bool _shapeOk(int? w, int? h) {
    if (w == null || h == null || w <= 0 || h <= 0) return true;
    final ratio = w / h;
    return ratio >= 0.5 && ratio <= 2.0 && min(w, h) >= 400;
  }

  static bool _fits(_Found f, String q) {
    final kind = f.kind?.trim() ?? '';
    if (kind.isNotEmpty && (!_pictureKind.hasMatch(kind) || _notPicture.hasMatch(kind))) return false;
    if (_notPictureTitle.hasMatch(f.art.title) || (kind.isEmpty && _notPicture.hasMatch(f.art.title))) return false;
    if (!_shapeOk(f.width, f.height)) return false;
    return _subjectRe(q)?.hasMatch(f.about) ?? true;
  }

  /// A random one of [found] that passes [_fits].
  static Artwork? _pick(List<_Found> found, String q, Random rng) =>
      ([...found]..shuffle(rng)).where((f) => _fits(f, q)).firstOrNull?.art;

  static int? _int(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');

  static String _stripTags(String? html) => (html ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();

  // ---- The collections ----

  /// How collections that search by keyword name a place.
  static const _placeWords = {
    'Iran': 'Persian', 'Egypt': 'Egyptian', 'India': 'Indian', 'Turkey': 'Ottoman', 'England': 'British', //
    'Germany': 'German', 'France': 'French', 'Russia': 'Russian', 'Ukraine': 'Ukrainian', 'Spain': 'Spanish',
    'Italy': 'Italian', 'Portugal': 'Portuguese', 'Netherlands': 'Dutch', 'Sweden': 'Swedish', 'Poland': 'Polish',
    'Greece': 'Greek', 'Israel': 'Hebrew', 'Japan': 'Japanese', 'China': 'Chinese', 'Korea': 'Korean',
    'Armenia': 'Armenian', 'Georgia': 'Georgian',
  };

  static String _query(String q, String? place) => place == null ? q : '$q ${_placeWords[place] ?? place}';

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
    // Most search hits fail the checks (pots, coins, the word only in a
    // credit line), so up to twelve are looked at, four at a time.
    for (var i = 0; i < 12 && i < ids.length; i += 4) {
      final objects = await Future.wait(ids.skip(i).take(4).map((id) async {
        try {
          return await Net.getJson('$_met/v1/objects/$id') as Map;
        } on Exception {
          return null;
        }
      }));
      final art = _pick([for (final o in objects) ?_metFound(o)], q, rng);
      if (art != null) return art;
    }
    return null;
  }

  static _Found? _metFound(Map? o) {
    if (o == null) return null;
    final small = o['primaryImageSmall'] as String? ?? '';
    if (o['isPublicDomain'] != true || small.isEmpty) return null;
    String? s(String k) => (o[k] as String?)?.trim().isEmpty ?? true ? null : (o[k] as String).trim();
    final tags = [for (final t in (o['tags'] as List? ?? const []).cast<Map>()) t['term']];
    final art = Artwork(
      imageUrl: small,
      fullUrl: s('primaryImage'),
      title: s('title') ?? 'Untitled',
      artist: s('artistDisplayName'),
      date: s('objectDate'),
      origin: s('country') ?? s('culture'),
      credit: 'The Met · Public domain',
      pageUrl: s('objectURL'),
    );
    return _Found(art, about: '${art.title} ${tags.join(' ')}', kind: '${s('classification') ?? ''} ${s('objectName') ?? ''}');
  }

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
    final found = <_Found>[];
    for (final a in (res['data'] as List? ?? const []).cast<Map>()) {
      final images = (a['images'] as Map?) ?? const {};
      final web = images['web'] as Map?;
      final url = web?['url'] as String?;
      if (url == null) continue;
      final creators = (a['creators'] as List? ?? const []).cast<Map>();
      final art = Artwork(
        imageUrl: url,
        fullUrl: (images['print'] as Map?)?['url'] as String? ?? url,
        title: a['title'] as String? ?? 'Untitled',
        artist: creators.isEmpty ? null : creators.first['description'] as String?,
        date: a['creation_date'] as String?,
        origin: (a['culture'] as List?)?.cast<String>().firstOrNull,
        credit: 'Cleveland Museum of Art · CC0',
        pageUrl: a['url'] as String?,
      );
      // The curators' description says what is pictured, so it counts too.
      found.add(_Found(art,
          about: '${art.title} ${_stripTags(a['description'] as String?)}',
          kind: a['type'] as String? ?? '',
          width: _int(web?['width']),
          height: _int(web?['height'])));
    }
    return _pick(found, q, rng);
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
    final found = <_Found>[];
    for (final a in (res['items'] as List? ?? const []).cast<Map>()) {
      final thumb = a['image_thumbnail'] as String?;
      if (thumb == null || a['public_domain'] != true) continue;
      final titles = (a['titles'] as List? ?? const []).cast<Map>();
      final title = (titles.where((t) => t['language'] == 'engelsk').firstOrNull ?? titles.firstOrNull)?['title'];
      final made = (a['production'] as List? ?? const []).cast<Map>().firstOrNull;
      final when = (a['production_date'] as List? ?? const []).cast<Map>().firstOrNull;
      final art = Artwork(
        imageUrl: thumb,
        fullUrl: a['image_native'] as String? ?? thumb,
        title: title as String? ?? 'Untitled',
        artist: made?['creator'] as String?,
        date: when?['period'] as String?,
        credit: 'SMK, National Gallery of Denmark · Public domain',
        pageUrl: a['frontend_url'] as String?,
      );
      found.add(_Found(art,
          about: titles.map((t) => t['title']).join(' '),
          kind: (a['object_names'] as List? ?? const []).cast<Map>().map((n) => n['name']).join(', '),
          width: _int(a['image_width']),
          height: _int(a['image_height'])));
    }
    return _pick(found, q, rng);
  }

  /// Object types Europeana is asked for (its `what` field covers types and
  /// subjects, in every language it knows).
  static const _europeanaKinds =
      'painting OR drawing OR print OR miniature OR engraving OR etching OR woodcut OR watercolour OR illumination '
      'OR textile OR sculpture OR photograph OR map OR manuscript OR calligraphy';

  /// Europeana, which gathers thousands of European museums. Only items marked
  /// public domain or CC0 are used. `api2demo` is Europeana's public demo key.
  static Future<Artwork?> _fromEuropeana(Random rng, {required String q, String? place, ({int from, int to})? era}) async {
    // Searched by title and type: a free-text search matches any field in any
    // language (an Estonian jacket came back for "moon").
    final words = q == _anySubject
        ? const <String>[]
        : _wordsFor(q).where((w) => RegExp(r'^[a-zà-ÿæøå]+\*?$').hasMatch(w)).take(14).toList();
    final query = [
      if (words.isNotEmpty) 'title:(${words.join(' OR ')})',
      'what:($_europeanaKinds)',
      if (place != null) _placeWords[place] ?? place,
    ].join(' AND ');
    final Map res;
    try {
      final params = <String, dynamic>{
        'wskey': const String.fromEnvironment('EUROPEANA_KEY', defaultValue: 'api2demo'),
        'query': query,
        'reusability': 'open',
        'media': 'true',
        'profile': 'rich',
        'rows': '40',
        // Without TYPE:IMAGE, scanned book pages (TEXT) come back too.
        'qf': ['TYPE:IMAGE', if (era != null) 'YEAR:[${era.from} TO ${era.to}]'],
      };
      res = await Net.getJson(Uri.https('api.europeana.eu', '/record/v2/search.json', params).toString()) as Map;
    } on Exception {
      return null;
    }
    String? first(Map a, String k) => (a[k] as List?)?.cast<Object?>().whereType<String>().firstOrNull;
    // Language maps ({"en": [...], "def": [...]}) without the "def" entries, which are mostly URIs.
    String words2(Object? m) => m is Map
        ? [for (final e in m.entries) if (e.key != 'def') ...(e.value as List? ?? const []).whereType<String>()].join(', ')
        : '';
    final found = <_Found>[];
    for (final a in (res['items'] as List? ?? const []).cast<Map>()) {
      final rights = first(a, 'rights') ?? '';
      if (!rights.contains('publicdomain') && !rights.contains('/zero/')) continue;
      final preview = first(a, 'edmPreview');
      if (preview == null) continue;
      final art = Artwork(
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
      found.add(_Found(art,
          about: '${(a['title'] as List? ?? const []).join(' ')} ${words2(a['dcSubjectLangAware'])}',
          kind: words2(a['dcTypeLangAware'])));
    }
    return _pick(found, q, rng);
  }

  /// Minneapolis Institute of Art (Mia), searched by title, picture types and
  /// country. It has no date filter, so it sits out the steps with an era.
  static Future<Artwork?> _fromMia(Random rng, {required String q, String? place, ({int from, int to})? era}) async {
    if (era != null) return null;
    final words = q == _anySubject ? const <String>[] : _wordsFor(q).where((w) => RegExp(r'^\p{L}+\*?$', unicode: true).hasMatch(w));
    final query = [
      if (words.isNotEmpty) 'title:(${words.join(' OR ')})',
      'classification:(Paintings OR Drawings OR Prints OR Manuscript OR Textiles OR Sculpture OR Photographs OR Calligraphy OR Documents)',
      'rights_type:"Public Domain"',
      'image:valid',
      if (place != null) 'country:"$place"',
    ].join(' AND ');
    final Map res;
    try {
      res = await Net.getJson('https://search.artsmia.org/${Uri.encodeComponent(query)}?size=40') as Map;
    } on Exception {
      return null;
    }
    final found = <_Found>[];
    for (final hit in ((res['hits'] as Map?)?['hits'] as List? ?? const []).cast<Map>()) {
      final a = (hit['_source'] as Map?) ?? const {};
      final id = a['id'];
      if (id == null || a['rights_type'] != 'Public Domain') continue;
      String? s(String k) => (a[k] as String?)?.trim().isEmpty ?? true ? null : (a[k] as String).trim();
      final origin = s('country') ?? s('culture');
      // Unknown makers are given as the place ("China"), which isn't an artist.
      final artist = s('artist');
      final image = 'https://${_int(id)! % 7 + 1}.api.artsmia.org/800/$id.jpg';
      final art = Artwork(
        imageUrl: image,
        fullUrl: image,
        title: s('title') ?? 'Untitled',
        artist: artist == origin || artist == 'Unidentified' ? null : artist,
        date: s('dated'),
        origin: origin,
        credit: 'Minneapolis Institute of Art · Public domain',
        pageUrl: 'https://collections.artsmia.org/art/$id',
      );
      found.add(_Found(art,
          about: art.title, kind: s('classification') ?? '', width: _int(a['image_width']), height: _int(a['image_height'])));
    }
    return _pick(found, q, rng);
  }

  /// One museum through Openverse, which mirrors several open collections that
  /// can't be reached directly from here (the Smithsonian's image server
  /// refuses Iranian addresses; Openverse's thumbnails don't). Its search
  /// joins words with AND and has no place or date filter, so both are
  /// checked on the museum's tags (a country, and decades such as "1640s").
  static _Collection _fromOpenverse(String source, String museum) =>
      (Random rng, {required String q, String? place, ({int from, int to})? era}) async {
        final Map res;
        try {
          res = await Net.getJson(Uri.https('api.openverse.org', '/v1/images/', {
            'q': q,
            'source': source,
            // Anonymous clients get at most 20 per page; more is refused.
            'page_size': '20',
          }).toString()) as Map;
        } on Exception {
          return null;
        }
        final found = <_Found>[];
        for (final r in (res['results'] as List? ?? const []).cast<Map>()) {
          final license = r['license'] as String? ?? '';
          final thumb = r['thumbnail'] as String?;
          if ((license != 'cc0' && license != 'pdm') || thumb == null) continue;
          final tags = [for (final t in (r['tags'] as List? ?? const []).cast<Map>()) '${t['name']}'];
          if (place != null && !tags.any((t) => t == place || t.contains(_placeWords[place] ?? place))) continue;
          if (era != null) {
            final years = [for (final t in tags) ?int.tryParse(RegExp(r'^(\d{4})s$').firstMatch(t)?.group(1) ?? '')];
            if (!years.any((y) => y + 99 >= era.from && y <= era.to)) continue;
          }
          final creator = _stripTags(r['creator'] as String?);
          final art = Artwork(
            imageUrl: thumb,
            fullUrl: r['url'] as String?,
            title: _stripTags(r['title'] as String?).isEmpty ? 'Untitled' : _stripTags(r['title'] as String?),
            artist: creator.isEmpty ? null : creator,
            date: null,
            origin: place,
            credit: '$museum · ${license == 'cc0' ? 'CC0' : 'Public domain'}',
            pageUrl: r['foreign_landing_url'] as String?,
          );
          found.add(_Found(art,
              about: '${art.title} ${tags.join(' ')}',
              kind: tags.join(', '),
              width: _int(r['width']),
              height: _int(r['height'])));
        }
        return _pick(found, q, rng);
      };

  /// Wikimedia Commons, the fallback: public domain only, and only files in a
  /// category for one of the accepted kinds of work.
  static Future<Artwork?> _fromCommons(Random rng, String q) async {
    final Map res;
    try {
      res = await Net.getJson(Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'generator': 'search',
        'gsrnamespace': '6',
        'gsrsearch': '$q painting filetype:bitmap',
        'gsrlimit': '40',
        'gsroffset': '${rng.nextInt(4) * 40}',
        'prop': 'imageinfo',
        'iiprop': 'url|size|extmetadata',
        'iiurlwidth': '900',
        'iiextmetadatafilter': 'ObjectName|Artist|DateTimeOriginal|LicenseShortName|Categories',
      }).toString()) as Map;
    } on Exception {
      return null;
    }
    final found = <_Found>[];
    for (final p in ((res['query'] as Map?)?['pages'] as Map? ?? const {}).values.cast<Map>()) {
      final info = ((p['imageinfo'] as List?)?.firstOrNull as Map?) ?? const {};
      final meta = (info['extmetadata'] as Map?) ?? const {};
      String m(String k) => _stripTags((meta[k] as Map?)?['value'] as String?);
      final license = m('LicenseShortName');
      // Public domain only, so a liked picture can be kept freely.
      if (!RegExp('public domain|cc0|pd', caseSensitive: false).hasMatch(license)) continue;
      final thumb = info['thumburl'] as String?;
      if (thumb == null) continue;
      final fileTitle = (p['title'] as String).replaceFirst('File:', '').replaceFirst(RegExp(r'\.\w+$'), '');
      final art = Artwork(
        imageUrl: thumb,
        fullUrl: info['url'] as String?,
        title: m('ObjectName').isEmpty ? fileTitle : m('ObjectName'),
        artist: m('Artist').isEmpty ? null : m('Artist'),
        date: m('DateTimeOriginal').isEmpty ? null : m('DateTimeOriginal'),
        credit: 'Wikimedia Commons · $license',
        pageUrl: info['descriptionurl'] as String?,
      );
      // Categories name both the kind of work and what it shows ("Moon in art").
      final categories = m('Categories').replaceAll('|', ', ');
      if (!_pictureKind.hasMatch(categories)) continue;
      found.add(_Found(art,
          about: '${art.title} $fileTitle $categories',
          kind: null,
          width: _int(info['width']),
          height: _int(info['height'])));
    }
    return _pick(found, q, rng);
  }
}
