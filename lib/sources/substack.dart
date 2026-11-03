import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/artwork.dart';
import '../models/languages.dart';
import '../models/reading.dart';
import '../services/net.dart';
import '../services/substack_account.dart';
import 'classify.dart';
import 'source.dart';

/// Posts from the Substack publications the user follows, as one source:
/// its share of the nights is split evenly between the publications, so
/// following fifty doesn't crowd out everything else.
///
/// Publications set to "by content" have each post sorted into story, poem
/// or essay (see [classify]); the verdict is remembered per post. Paid posts
/// are included only when the user's own account has a paid subscription.
class SubstackSource extends ReadingSource {
  static const sourceId = 'substack';
  static const _kindsKey = 'substack:kinds';
  static const _langsKey = 'substack:langs';

  final List<SubstackPub> Function() pubs;
  final SubstackAccount account;
  final SharedPreferences? prefs;

  SubstackSource(this.pubs, this.account, [this.prefs]);

  @override
  String get id => sourceId;
  @override
  String get name => 'Substack';
  @override
  String get description {
    final on = pubs().where((p) => p.on).length;
    return '$on publication${on == 1 ? '' : 's'} you follow, sorted by content';
  }

  @override
  ReadingType get type => ReadingType.essay;
  @override
  Set<ReadingType> get types => {
        for (final p in pubs().where((p) => p.on)) ...p.type == null ? ReadingType.values : [p.type!],
      };
  @override
  String get lang => 'auto';

  /// Each publication's language, learned from its posts.
  Map<String, String> get pubLangs =>
      (jsonDecode(prefs?.getString(_langsKey) ?? '{}') as Map).cast<String, String>();

  @override
  Set<String> get langs {
    final known = pubLangs;
    return {for (final p in pubs()) if (p.on && known['${p.id}'] != null) known['${p.id}']!};
  }

  @override
  bool get unknownLang {
    final known = pubLangs;
    return pubs().any((p) => p.on && known['${p.id}'] == null);
  }
  @override
  bool get builtIn => false;

  @override
  Future<Reading> fetch(Random rng) => fetchFor(type, rng);

  @override
  Future<Reading> fetchFor(ReadingType want, Random rng, {String? lang}) async {
    final known = pubLangs;
    final candidates = pubs()
        .where((p) => p.on && (p.type == null || p.type == want))
        .where((p) => lang == null || known['${p.id}'] == null || known['${p.id}'] == lang)
        .toList()
      ..shuffle(rng);
    if (candidates.isEmpty) throw SourceException('Substack: no followed publication is set to ${want.label.toLowerCase()}s');
    final failures = <String>[];
    for (final pub in candidates.take(4)) {
      try {
        final r = await _fromPub(pub, want, rng);
        if (r != null) return r;
      } on RateLimitedException {
        rethrow;
      } on SourceException catch (e) {
        failures.add('${pub.name}: $e');
      }
    }
    throw SourceException(failures.isEmpty
        ? 'Substack: no ${want.label.toLowerCase()} found in recent posts'
        : 'Substack: ${failures.join('; ')}');
  }

  Map<String, String> get _kinds =>
      (jsonDecode(prefs?.getString(_kindsKey) ?? '{}') as Map).cast<String, String>();

  Future<void> _remember(Object postId, ReadingType kind) async {
    final kinds = _kinds..['$postId'] = kind.name;
    if (kinds.length > 3000) kinds.remove(kinds.keys.first);
    await prefs?.setString(_kindsKey, jsonEncode(kinds));
  }

  Future<Reading?> _fromPub(SubstackPub pub, ReadingType want, Random rng) async {
    // The archive is public; it lists posts with their audience and length.
    final offset = rng.nextInt(3) * 25;
    final kinds = _kinds;
    final posts = (await Net.getJson('https://${pub.host}/api/v1/archive?sort=new&offset=$offset&limit=25') as List)
        .cast<Map>()
        .where((p) {
          final words = p['wordcount'] as int? ?? 0;
          final readable = p['audience'] == 'everyone' || pub.paid;
          final known = kinds['${p['id']}'];
          final kindOk = pub.type != null || known == null || known == want.name;
          // Poems can be short; stories and essays need some length.
          final minWords = want == ReadingType.poem ? 40 : 300;
          return p['type'] == 'newsletter' && readable && kindOk && words >= minWords && words <= 9000;
        })
        .toList()
      ..shuffle(rng);

    for (final p in posts.take(pub.type == null ? 5 : 3)) {
      // Full text comes from substack.com, where the user's session applies.
      final data = await account.getJson('/api/v1/posts/by-id/${p['id']}') as Map;
      final post = (data['post'] ?? data) as Map;
      final body = htmlToText(post['body_html'] as String? ?? '');
      if (body.length < (want == ReadingType.poem ? 150 : 800)) continue; // Paywalled preview or an empty post.
      final title = post['title'] as String? ?? p['title'] as String? ?? pub.name;
      if (pub.type == null) {
        final kind = classify(
          title: title,
          subtitle: post['subtitle'] as String?,
          tags: [for (final t in (post['postTags'] as List? ?? p['postTags'] as List? ?? const []).cast<Map>()) '${t['name']}'],
          section: post['section_name'] as String? ?? p['section_name'] as String?,
          text: body,
        );
        await _remember(p['id'] as Object, kind);
        if (kind != want) continue;
      }
      final language = normalizeLang(post['language'] as String?) ?? detectLang('$title $body');
      await prefs?.setString(_langsKey, jsonEncode(pubLangs..['${pub.id}'] = language));
      final bylines = (post['publishedBylines'] as List?)?.cast<Map>() ?? const [];
      final author = bylines.isNotEmpty ? bylines.first['name'] as String? : null;
      final url = post['canonical_url'] as String? ?? p['canonical_url'] as String? ?? 'https://${pub.host}';
      // The post's own cover image stands in for a museum picture.
      final cover = (post['cover_image'] ?? p['cover_image']) as String?;
      return Reading(
        type: want,
        title: title,
        author: author,
        body: body,
        sourceId: id,
        sourceName: pub.name,
        url: url,
        lang: language,
        art: cover == null || cover.isEmpty
            ? null
            : Artwork(
                imageUrl: cover,
                title: title,
                artist: author ?? pub.name,
                credit: '${pub.name} · cover image of the post',
                pageUrl: url,
              ),
      );
    }
    return null;
  }
}
