import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/artwork.dart';
import '../models/reading.dart';
import '../theme.dart';
import '../sources/feed.dart';
import '../sources/notion_atlas.dart';
import '../sources/registry.dart';
import '../sources/source.dart';
import '../sources/substack.dart';
import 'art_finder.dart';
import 'net.dart';
import 'notion_account.dart';
import 'substack_account.dart';
import 'translator.dart';

/// The three readings chosen for one night.
class Night {
  final String date; // yyyy-MM-dd
  final Map<ReadingType, Reading> readings;
  final Set<ReadingType> finished;

  Night(this.date, [Map<ReadingType, Reading>? readings, Set<ReadingType>? finished])
      : readings = readings ?? {},
        finished = finished ?? {};

  Map<String, dynamic> toJson() => {
        'date': date,
        'readings': {for (final e in readings.entries) e.key.name: e.value.toJson()},
        'finished': finished.map((t) => t.name).toList(),
      };

  factory Night.fromJson(Map<String, dynamic> j) => Night(
        j['date'] as String,
        {
          for (final e in (j['readings'] as Map).entries)
            ReadingType.values.byName(e.key as String): Reading.fromJson((e.value as Map).cast()),
        },
        {for (final t in (j['finished'] as List? ?? const [])) ReadingType.values.byName(t as String)},
      );
}

/// App-wide state: sources, tonight's selection, history, favourites and settings.
class Library extends ChangeNotifier {
  Library._(this._prefs);

  static Future<Library> load() async {
    final lib = Library._(await SharedPreferences.getInstance());
    await lib.substack.load();
    await lib.notion.load(lib._prefs);
    lib._restore();
    return lib;
  }

  final SharedPreferences _prefs;
  final List<CatalogEntry> catalogEntries = catalog();
  late Set<String> _added;
  List<FeedSource> _custom = [];
  final SubstackAccount substack = SubstackAccount();
  List<SubstackPub> substackPubs = [];
  late final SubstackSource substackSource = SubstackSource(() => substackPubs, substack, _prefs);
  final NotionAccount notion = NotionAccount();
  late final NotionAtlasSource atlas = NotionAtlasSource(notion, _prefs);
  final Map<String, bool> _enabled = {};
  final Map<String, int> _weights = {};
  late Night tonight;
  final Map<ReadingType, String> errors = {};
  final Set<ReadingType> loading = {};
  List<Reading> favorites = [];

  AppTheme theme = AppTheme.dark;

  /// Whether each reading gets a work of art from a museum collection.
  bool artOn = true;
  double textScale = 1.0;
  bool reminderOn = false;
  TimeOfDay reminderTime = const TimeOfDay(hour: 21, minute: 30);

  /// The user's sources: catalog entries they added, their own feeds, and
  /// the connected accounts.
  List<ReadingSource> get sources => [
        for (final e in catalogEntries)
          if (_added.contains(e.id)) e.source,
        ..._custom,
        if (substackPubs.isNotEmpty) substackSource,
        if (notion.signedIn) atlas,
      ];
  bool isEnabled(ReadingSource s) => _enabled[s.id] ?? true;

  /// The Substack username whose follows are read; null when not connected.
  String? get substackHandle => _prefs.getString('substack:handle');

  // Chances

  static const defaultWeight = 5;
  static const maxWeight = 10;

  /// How strongly [s] is preferred for [type], 1–[maxWeight]. A source's
  /// chance is its weight over the total of the switched-on sources, whatever
  /// the size of its collection.
  int weight(ReadingSource s, ReadingType type) => _weights['${type.name}:${s.id}'] ?? defaultWeight;

  /// Switched-on sources that can supply [type].
  List<ReadingSource> active(ReadingType type) =>
      sources.where((s) => s.types.contains(type) && isEnabled(s)).toList();

  /// The chance (0–1) that tonight's [type] is drawn from [s] first.
  /// It follows the real draw: a language by its weight, then a source in it
  /// by the sources' weights (sources of unknown language count in every one).
  double chance(ReadingSource s, ReadingType type) {
    if (!isEnabled(s) || !s.types.contains(type)) return 0;
    final pool = active(type);
    double share(Iterable<ReadingSource> among) {
      final total = among.fold<int>(0, (sum, a) => sum + weight(a, type));
      return total == 0 ? 0 : weight(s, type) / total;
    }

    final langs = languagesFor(type).where((l) => langWeight(l) > 0).toList();
    if (langs.isEmpty) return s.langs.isEmpty ? share(pool.where((a) => a.langs.isEmpty)) : 0;
    final totalLang = langs.fold<int>(0, (sum, l) => sum + langWeight(l));
    var p = 0.0;
    for (final l in langs) {
      final inLang = pool.where((a) => a.langs.contains(l) || a.unknownLang);
      if (s.langs.contains(l) || s.unknownLang) p += langWeight(l) / totalLang * share(inLang);
    }
    return p;
  }

  Future<void> setWeight(ReadingSource s, ReadingType type, int w) async {
    final key = '${type.name}:${s.id}';
    _weights[key] = w.clamp(1, maxWeight);
    await _prefs.setInt('weight:$key', _weights[key]!);
    notifyListeners();
  }

  /// Gives every source of [type] the same chance again.
  Future<void> evenOut(ReadingType type) async {
    for (final s in sources) {
      final key = '${type.name}:${s.id}';
      _weights.remove(key);
      await _prefs.remove('weight:$key');
    }
    notifyListeners();
  }

  /// A random order where each source comes earlier in proportion to its
  /// weight (Efraimidis–Spirakis), so a strong favourite usually goes first
  /// but the rest still serve as fallbacks.
  List<ReadingSource> weightedOrder(ReadingType type, Random rng) =>
      _weighted([for (final s in active(type)) (s, weight(s, type).toDouble())], rng);

  static List<T> _weighted<T>(List<(T, double)> items, Random rng) {
    final keyed = [
      for (final (item, w) in items)
        if (w > 0) (item, pow(rng.nextDouble(), 1 / w).toDouble()),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final k in keyed) k.$1];
  }

  static String _pluralOf(ReadingType t) => switch (t) {
        ReadingType.story => 'stories',
        ReadingType.poem => 'poems',
        ReadingType.essay => 'essays',
      };

  // Languages

  static const defaultLangWeight = 50;

  /// The languages the user's switched-on sources are known to come in.
  List<String> get languages {
    final found = <String>{for (final s in sources.where(isEnabled)) ...s.langs};
    return found.toList()..sort((a, b) => langWeight(b).compareTo(langWeight(a)));
  }

  /// How much the user wants [code], 0–100; 0 means never.
  int langWeight(String code) => _prefs.getInt('langWeight:$code') ?? defaultLangWeight;

  Future<void> setLangWeight(String code, int w) async {
    await _prefs.setInt('langWeight:$code', w.clamp(0, 100));
    notifyListeners();
  }

  Future<void> evenOutLanguages() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith('langWeight:')).toList()) {
      await _prefs.remove(k);
    }
    notifyListeners();
  }

  /// Languages that can supply [type] tonight.
  Set<String> languagesFor(ReadingType type) => {for (final s in active(type)) ...s.langs};

  /// The share (0–1) of nights' [type] in [code], among the languages that
  /// [type] can come in. Without a type: among all the user's languages.
  double langShare(String code, [ReadingType? type]) {
    final pool = type == null ? languages.toSet() : languagesFor(type);
    if (!pool.contains(code)) return 0;
    final total = pool.fold<int>(0, (s, c) => s + langWeight(c));
    return total == 0 ? 0 : langWeight(code) / total;
  }

  /// What to try, in order: a language is drawn by its weight, then the
  /// sources in it by theirs. Sources whose language isn't known yet are
  /// tried under any language. Languages set to 0 are left out.
  List<(ReadingSource, String?)> attemptOrder(ReadingType type, Random rng) {
    final bySource = weightedOrder(type, rng);
    final langs = _weighted([for (final l in languagesFor(type)) (l, langWeight(l).toDouble())], rng);
    final out = <(ReadingSource, String?)>[];
    final tried = <String>{};
    for (final l in langs) {
      for (final s in bySource.where((s) => s.langs.contains(l) || s.unknownLang)) {
        // Single-language sources only need one try.
        final key = s.langs.length > 1 || s.unknownLang ? '${s.id}|$l' : s.id;
        if (tried.add(key)) out.add((s, l));
      }
    }
    // Sources with no known language at all (a brand-new feed).
    for (final s in bySource.where((s) => s.langs.isEmpty)) {
      if (tried.add('${s.id}|')) out.add((s, null));
    }
    return out;
  }

  /// A feed added before its language was known takes the first reading's.
  Future<void> _learnLang(ReadingSource s, Reading r) async {
    final i = _custom.indexWhere((c) => c.id == s.id);
    if (i < 0 || _custom[i].language != null) return;
    _custom[i] = _custom[i].copyWith(language: r.lang);
    await _saveCustom();
  }

  Future<void> setFeedLanguage(FeedSource s, String code) async {
    _custom = [for (final c in _custom) c.id == s.id ? c.copyWith(language: code) : c];
    await _saveCustom();
  }

  // Translation

  TranslatorKind get translatorKind =>
      TranslatorKind.values.asNameMap()[_prefs.getString('translator')] ?? TranslatorKind.google;
  String get translateTo => _prefs.getString('translateTo') ?? 'en';
  String? get libreUrl => _prefs.getString('libreUrl');
  String? get libreKey => _prefs.getString('libreKey');

  Future<void> setTranslation({TranslatorKind? kind, String? to, String? libreUrl, String? libreKey}) async {
    if (kind != null) await _prefs.setString('translator', kind.name);
    if (to != null) await _prefs.setString('translateTo', to);
    if (libreUrl != null) await _prefs.setString('libreUrl', libreUrl.trim());
    if (libreKey != null) await _prefs.setString('libreKey', libreKey.trim());
    notifyListeners();
  }

  /// The language this source's readings are always shown in, if set.
  String? autoTranslate(String sourceId) => _prefs.getString('translate:$sourceId');

  Future<void> setAutoTranslate(ReadingSource s, String? code) async {
    code == null ? await _prefs.remove('translate:${s.id}') : await _prefs.setString('translate:${s.id}', code);
    notifyListeners();
  }

  /// A saved translation of [r] into [to], if one was made before.
  ({String title, String body})? cachedTranslation(Reading r, String to) {
    final raw = _prefs.getString('tr:$to:${r.key}');
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map;
    return (title: j['title'] as String, body: j['body'] as String);
  }

  /// Translates [r] into [to] with the chosen service, and keeps the result.
  Future<({String title, String body})> translate(Reading r, String to) async {
    final cached = cachedTranslation(r, to);
    if (cached != null) return cached;
    final t = Translator(translatorKind, libreUrl: libreUrl, libreKey: libreKey);
    final title = await t.translate(r.title, from: r.lang, to: to);
    final body = await t.translate(r.body, from: r.lang, to: to);
    final key = 'tr:$to:${r.key}';
    await _prefs.setString(key, jsonEncode({'title': title, 'body': body}));
    // Keep the newest 60 translations.
    final keys = [...?_prefs.getStringList('translations')?.where((k) => k != key), key];
    for (final old in keys.length > 60 ? keys.sublist(0, keys.length - 60) : const <String>[]) {
      await _prefs.remove(old);
    }
    await _prefs.setStringList('translations', keys.length > 60 ? keys.sublist(keys.length - 60) : keys);
    return (title: title, body: body);
  }

  /// The reading "night" rolls over at 4 am, so a session after midnight
  /// still belongs to the evening it started in.
  static String nightKey([DateTime? at]) {
    final t = (at ?? DateTime.now()).subtract(const Duration(hours: 4));
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  void _restore() {
    final p = _prefs;
    // Publications saved by the old sign-in-only version, with no username,
    // can't be refreshed or disconnected; start over instead.
    substackPubs = p.getString('substack:handle') == null
        ? []
        : (p.getStringList('substackPubs') ?? const [])
            .map((s) => SubstackPub.fromJson(jsonDecode(s) as Map<String, dynamic>))
            .toList();
    _custom = (p.getStringList('customSources') ?? const [])
        .map((s) => FeedSource.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    _added = (p.getStringList('catalog:added') ?? [for (final e in catalogEntries) if (e.starter) e.id]).toSet();
    for (final s in [...catalogEntries.map((e) => e.source), ..._custom, substackSource, atlas]) {
      final v = p.getBool('enabled:${s.id}');
      if (v != null) _enabled[s.id] = v;
    }
    for (final k in p.getKeys().where((k) => k.startsWith('weight:'))) {
      _weights[k.substring(7)] = p.getInt(k) ?? defaultWeight;
    }
    favorites = (p.getStringList('favorites') ?? const [])
        .map((s) => Reading.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    theme = AppTheme.fromName(p.getString('appTheme') ?? p.getString('themeMode'));
    artOn = p.getBool('artOn') ?? true;
    textScale = p.getDouble('textScale') ?? 1.0;
    reminderOn = p.getBool('reminderOn') ?? false;
    reminderTime = TimeOfDay(hour: p.getInt('reminderHour') ?? 21, minute: p.getInt('reminderMinute') ?? 30);
    tonight = nightFor(nightKey()) ?? Night(nightKey());
  }

  Night? nightFor(String date) {
    final raw = _prefs.getString('night:$date');
    return raw == null ? null : Night.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Past nights, newest first.
  List<Night> history() => (_prefs.getStringList('nights') ?? const [])
      .reversed
      .map(nightFor)
      .whereType<Night>()
      .where((n) => n.readings.isNotEmpty)
      .toList();

  /// Nights kept in Past nights; older ones (full texts) are dropped so the
  /// saved data doesn't grow for ever. Saved readings are kept separately.
  static const keepNights = 120;

  Future<void> _saveNight(Night n) async {
    await _prefs.setString('night:${n.date}', jsonEncode(n.toJson()));
    final dates = _prefs.getStringList('nights') ?? [];
    if (dates.contains(n.date)) return;
    final all = [...dates, n.date];
    final drop = all.length > keepNights ? all.sublist(0, all.length - keepNights) : const <String>[];
    for (final d in drop) {
      await _prefs.remove('night:$d');
    }
    await _prefs.setStringList('nights', all.sublist(drop.length));
  }

  /// Fills in whatever tonight is still missing. Safe to call repeatedly,
  /// e.g. on app resume; a new night starts fresh after 4 am.
  Future<void> ensureTonight() async {
    if (tonight.date != nightKey()) {
      tonight = nightFor(nightKey()) ?? Night(nightKey());
      errors.clear();
      notifyListeners();
    }
    final missing = ReadingType.values.where((t) => !tonight.readings.containsKey(t) && !loading.contains(t));
    await Future.wait(missing.map(_fill));
    // Readings fetched while offline get their picture once back online.
    for (final t in ReadingType.values) {
      if (tonight.readings[t]?.art == null) unawaited(_attachArt(tonight, t));
    }
  }

  final Set<String> _artTried = {};

  /// Looks for a work of art for one of [night]'s readings, without holding
  /// the reading up. Tried once per reading per session.
  Future<void> _attachArt(Night night, ReadingType type) async {
    final r = night.readings[type];
    if (!artOn || r == null || r.art != null || r.sourceId == SubstackSource.sourceId || !_artTried.add(r.key)) return;
    final Artwork? art;
    try {
      art = await findArt(r, Random());
    } catch (_) {
      _artTried.remove(r.key);
      return;
    }
    if (art == null) {
      _artTried.remove(r.key); // Offline or nothing found: try again on the next resume.
      return;
    }
    if (night.readings[type]?.key != r.key) return;
    night.readings[type] = r.withArt(art);
    await _saveNight(night);
    notifyListeners();
  }

  /// The art search; a field so tests can replace it.
  Future<Artwork?> Function(Reading r, Random rng) findArt = ArtFinder.find;

  // Liked artworks

  List<Artwork> get likedArt => [
        for (final s in _prefs.getStringList('likedArt') ?? const <String>[])
          Artwork.fromJson(jsonDecode(s) as Map<String, dynamic>),
      ];

  bool isArtLiked(Artwork a) => likedArt.any((l) => l.imageUrl == a.imageUrl);

  Future<void> toggleArtLike(Artwork a) async {
    final list = likedArt;
    isArtLiked(a) ? list.removeWhere((l) => l.imageUrl == a.imageUrl) : list.insert(0, a);
    await _prefs.setStringList('likedArt', [for (final l in list) jsonEncode(l.toJson())]);
    notifyListeners();
  }

  /// Swaps one of tonight's readings for a different one.
  Future<void> reroll(ReadingType type) => _fill(type, replace: true);

  Future<void> _fill(ReadingType type, {bool replace = false}) async {
    if (loading.contains(type)) return;
    loading.add(type);
    errors.remove(type);
    notifyListeners();
    try {
      final reading = await _fetchFresh(type, avoidSource: replace ? tonight.readings[type]?.sourceId : null);
      tonight.readings[type] = reading;
      tonight.finished.remove(type);
      await _markSeen(reading);
      await _saveNight(tonight);
      unawaited(_attachArt(tonight, type));
    } catch (e) {
      // Errors too (a malformed reply failing a cast), so the card never hangs.
      errors[type] = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading.remove(type);
      notifyListeners();
    }
  }

  /// Tries enabled sources in a weighted random order until one returns something unseen.
  Future<Reading> _fetchFresh(ReadingType type, {String? avoidSource}) async {
    final rng = Random();
    if (active(type).isEmpty) throw Exception('No ${type.label.toLowerCase()} sources are switched on');
    final candidates = attemptOrder(type, rng);
    if (candidates.isEmpty) throw Exception('Every language with ${_pluralOf(type)} is set to 0 in Settings');
    // Prefer a different source when rerolling, but fall back to the same one.
    if (avoidSource != null) {
      final others = candidates.where((c) => c.$1.id != avoidSource).toList();
      if (others.isNotEmpty) candidates.setAll(0, [...others, ...candidates.where((c) => c.$1.id == avoidSource)]);
    }
    final seen = (_prefs.getStringList('seen') ?? const []).toSet();
    final failures = <String>[];
    final failed = <String>{};
    for (final (source, lang) in candidates) {
      if (failed.contains(source.id)) continue;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final r = await source.fetchFor(type, rng, lang: lang);
          if (seen.contains(r.key) && attempt == 0) continue;
          await _learnLang(source, r);
          return r;
        } catch (e) {
          // Any failure, including a malformed reply (a TypeError), moves on
          // to the next source.
          failures.add('${source.name}: $e');
          // Only sources that serve one language at a time are worth trying
          // again for another language.
          if (source is! SubstackSource && source is! NotionAtlasSource) failed.add(source.id);
          break;
        }
      }
    }
    throw Exception(failures.isEmpty ? 'Nothing new found' : failures.join('\n'));
  }

  Future<void> _markSeen(Reading r) async {
    final seen = _prefs.getStringList('seen') ?? [];
    seen.add(r.key);
    await _prefs.setStringList('seen', seen.length > 2000 ? seen.sublist(seen.length - 2000) : seen);
  }

  Future<void> setFinished(Night night, ReadingType type, bool done) async {
    done ? night.finished.add(type) : night.finished.remove(type);
    await _saveNight(night);
    notifyListeners();
    final r = night.readings[type];
    if (done && r?.sourceId == NotionAtlasSource.sourceId && notion.signedIn && notion.syncRead) {
      try {
        await notion.markRead(r!.url);
      } on Exception catch (e) {
        debugPrint('Could not mark "${r!.title}" as read in Notion: $e');
      }
    }
  }

  // Favourites

  bool isFavorite(Reading r) => favorites.any((f) => f.key == r.key);

  Future<void> toggleFavorite(Reading r) async {
    isFavorite(r) ? favorites.removeWhere((f) => f.key == r.key) : favorites.insert(0, r);
    await _prefs.setStringList('favorites', favorites.map((f) => jsonEncode(f.toJson())).toList());
    notifyListeners();
  }

  // Sources

  Future<void> setEnabled(ReadingSource s, bool on) async {
    _enabled[s.id] = on;
    await _prefs.setBool('enabled:${s.id}', on);
    notifyListeners();
  }

  /// Adds a feed; a null [type] sorts each entry by its content.
  Future<void> addFeed(
      {required String name, required String url, required ReadingType? type, String? lang, bool site = false}) async {
    _custom.add(FeedSource(
        id: 'feed-${DateTime.now().millisecondsSinceEpoch}', name: name, type: type, url: url, language: lang, site: site));
    await _saveCustom();
  }

  Future<void> setFeedType(FeedSource s, ReadingType? type) async {
    _custom = [for (final c in _custom) c.id == s.id ? c.copyWith(type: () => type) : c];
    await _saveCustom();
  }

  Future<void> removeFeed(FeedSource s) async {
    _custom.removeWhere((c) => c.id == s.id);
    await _forget(s);
    await _saveCustom();
  }

  bool isAdded(CatalogEntry e) => _added.contains(e.id);

  Future<void> addFromCatalog(CatalogEntry e) async {
    _added.add(e.id);
    await _prefs.setStringList('catalog:added', _added.toList());
    notifyListeners();
  }

  /// Takes a catalog source off the user's list; it can be added back later.
  Future<void> removeFromList(ReadingSource s) async {
    if (s is FeedSource && _custom.any((c) => c.id == s.id)) return removeFeed(s);
    _added.remove(s.id);
    await _forget(s);
    await _prefs.setStringList('catalog:added', _added.toList());
    notifyListeners();
  }

  Future<void> _forget(ReadingSource s) async {
    _enabled.remove(s.id);
    await _prefs.remove('enabled:${s.id}');
    for (final t in ReadingType.values) {
      _weights.remove('${t.name}:${s.id}');
      await _prefs.remove('weight:${t.name}:${s.id}');
    }
  }

  // Substack

  /// Reads the publications a Substack user follows from their public profile.
  /// Accepts a username, `@name` or a profile link. No sign-in needed.
  Future<int> connectSubstack(String input) async {
    final handle = SubstackAccount.parseHandle(input);
    if (handle == null) throw SourceException('That doesn\'t look like a Substack username or profile link');
    await _loadFollows(handle);
    await _prefs.setString('substack:handle', handle);
    notifyListeners();
    return substackPubs.length;
  }

  /// Re-reads the follow list, keeping each publication's settings.
  Future<void> refreshSubstack() async {
    final handle = substackHandle;
    if (handle == null) throw SourceException('Substack isn\'t connected');
    await _loadFollows(handle);
  }

  Future<void> _loadFollows(String handle) async {
    final old = {for (final p in substackPubs) p.id: p};
    final fresh = await substack.follows(handle);
    substackPubs = [
      for (final p in fresh)
        if (old[p.id] case final o?) o.copyWith(paid: p.paid) else p,
    ];
    await _saveSubstack();
  }

  /// Sets whether a publication is used and what its posts count as
  /// (null: sorted by content).
  Future<void> setSubstackPub(SubstackPub pub, {ReadingType? Function()? type, bool? on}) async {
    substackPubs = [for (final p in substackPubs) p.id == pub.id ? p.copyWith(type: type, on: on) : p];
    await _saveSubstack();
  }

  /// Stores a session from the optional sign-in, which only unlocks paid posts.
  /// A session that Substack doesn't recognise is discarded.
  Future<void> signInSubstack(String session) async {
    await substack.signIn(session);
    try {
      await substack.getJson('/api/v1/subscriptions');
    } on Exception {
      await substack.signOut();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> signOutSubstack() async {
    await substack.signOut();
    notifyListeners();
  }

  /// Forgets the username, the publications and any session.
  Future<void> disconnectSubstack() async {
    await substack.signOut();
    await _prefs.remove('substack:handle');
    substackPubs = [];
    await _forget(substackSource);
    await _saveSubstack();
  }

  // Notion (Reading Atlas)

  /// Saves the token, finds the database with a "Nightly read" checkbox and
  /// checks it by loading the nightly reads. Returns how many were found.
  Future<int> connectNotion(String token, {String? database}) async {
    try {
      await notion.signIn(token, database: database);
      final n = (await notion.shortSources(refresh: true)).length;
      notifyListeners();
      return n;
    } on Exception {
      await notion.signOut(); // A token that can't read the database is no use.
      rethrow;
    }
  }

  /// Finishes "Connect with Notion": swaps the sign-in code for a token.
  Future<int> connectNotionWithCode(String code) async => connectNotion(await NotionAccount.exchangeCode(code));

  /// Starts "Connect with Notion": the page to open in the browser. The
  /// state is kept in storage, as Android may close the app meanwhile.
  Future<Uri> startNotionSignIn() async {
    final rng = Random.secure();
    final state = List.generate(24, (_) => rng.nextInt(16).toRadixString(16)).join();
    await _prefs.setString('notion:oauthState', state);
    return NotionAccount.authorizeUrl(state);
  }

  /// Whether [link] is Notion's sign-in coming back to the app.
  static bool isNotionCallback(Uri link) => link.toString().startsWith(NotionAccount.redirectUri);

  /// Finishes the sign-in from the link Notion sent back: checks that it
  /// answers our own request, then connects. Returns the nightly reads found.
  Future<int> finishNotionSignIn(Uri link) async {
    final expected = _prefs.getString('notion:oauthState');
    await _prefs.remove('notion:oauthState');
    final p = link.queryParameters;
    if (expected == null || p['state'] != expected) {
      throw SourceException('That sign-in reply wasn\'t for this app; try Connect with Notion again');
    }
    if (p['error'] != null) {
      throw SourceException(p['error'] == 'access_denied' ? 'Notion access was declined' : 'Notion: ${p['error']}');
    }
    final code = p['code'];
    if (code == null) throw SourceException('Notion sent no sign-in code');
    return connectNotionWithCode(code);
  }

  Future<void> useNotionDatabase(NotionDatabase db) async {
    await notion.useDatabase(db);
    await notion.shortSources(refresh: true);
    notifyListeners();
  }

  Future<void> refreshNotion() async {
    await notion.shortSources(refresh: true);
    notifyListeners();
  }

  Future<void> setNotionSyncRead(bool v) async {
    await notion.setSyncRead(v);
    notifyListeners();
  }

  Future<void> disconnectNotion() async {
    await notion.signOut();
    notifyListeners();
  }

  Future<void> _saveSubstack() async {
    await _prefs.setStringList('substackPubs', substackPubs.map((p) => jsonEncode(p.toJson())).toList());
    notifyListeners();
  }

  Future<void> _saveCustom() async {
    await _prefs.setStringList('customSources', _custom.map((c) => jsonEncode(c.toJson())).toList());
    notifyListeners();
  }

  // Settings

  Future<void> setArtOn(bool on) async {
    artOn = on;
    await _prefs.setBool('artOn', on);
    notifyListeners();
  }

  Future<void> setTheme(AppTheme t) async {
    theme = t;
    await _prefs.setString('appTheme', t.name);
    notifyListeners();
  }

  static const minTextScale = 0.8;
  static const maxTextScale = 1.8;

  Future<void> setTextScale(double v) async {
    textScale = ((v * 10).round() / 10).clamp(minTextScale, maxTextScale);
    await _prefs.setDouble('textScale', textScale);
    notifyListeners();
  }

  Future<void> setReminder(bool on, TimeOfDay time) async {
    reminderOn = on;
    reminderTime = time;
    await _prefs.setBool('reminderOn', on);
    await _prefs.setInt('reminderHour', time.hour);
    await _prefs.setInt('reminderMinute', time.minute);
    notifyListeners();
  }
}
