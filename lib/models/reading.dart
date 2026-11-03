import 'artwork.dart';
import 'languages.dart';

enum ReadingType { story, poem, essay }

extension ReadingTypeLabel on ReadingType {
  String get label => switch (this) {
        ReadingType.story => 'Short story',
        ReadingType.poem => 'Poem',
        ReadingType.essay => 'Essay',
      };

  /// One word, for chips and menus.
  String get shortLabel => switch (this) {
        ReadingType.story => 'Story',
        ReadingType.poem => 'Poem',
        ReadingType.essay => 'Essay',
      };
}

/// A single piece of text to read, as fetched from a source.
class Reading {
  final ReadingType type;
  final String title;
  final String? author;
  final String body;
  final String sourceId;
  final String sourceName;
  final String url;

  /// ISO 639-1 code ('fa', 'en', 'ru'…); decides text direction in the reader.
  final String lang;
  final DateTime fetchedAt;

  /// A work of art shown with it, when one was found (or the post's own cover).
  final Artwork? art;

  Reading({
    required this.type,
    required this.title,
    this.author,
    required this.body,
    required this.sourceId,
    required this.sourceName,
    required this.url,
    required this.lang,
    DateTime? fetchedAt,
    this.art,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  Reading withArt(Artwork? a) => Reading(
        type: type,
        title: title,
        author: author,
        body: body,
        sourceId: sourceId,
        sourceName: sourceName,
        url: url,
        lang: lang,
        fetchedAt: fetchedAt,
        art: a,
      );

  bool get isRtl => isRtlLang(lang);

  /// Stable identity used to avoid repeating the same piece.
  String get key => '$sourceId|$url';

  int get wordCount => body.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  /// Rough reading time at ~200 words per minute.
  int get minutes => (wordCount / 200).ceil().clamp(1, 999);

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'title': title,
        'author': author,
        'body': body,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'url': url,
        'lang': lang,
        'fetchedAt': fetchedAt.toIso8601String(),
        if (art != null) 'art': art!.toJson(),
      };

  factory Reading.fromJson(Map<String, dynamic> j) => Reading(
        type: ReadingType.values.byName(j['type'] as String),
        title: j['title'] as String,
        author: j['author'] as String?,
        body: j['body'] as String,
        sourceId: j['sourceId'] as String,
        sourceName: j['sourceName'] as String,
        url: j['url'] as String,
        lang: j['lang'] as String,
        fetchedAt: DateTime.parse(j['fetchedAt'] as String),
        art: j['art'] == null ? null : Artwork.fromJson((j['art'] as Map).cast()),
      );
}
