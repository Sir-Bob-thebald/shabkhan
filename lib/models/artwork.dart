/// A work of art shown with a reading: from a museum's open-access
/// collection, or a Substack post's own cover image.
class Artwork {
  /// A screen-sized image.
  final String imageUrl;

  /// The largest image, for saving; falls back to [imageUrl].
  final String? fullUrl;
  final String title;
  final String? artist;

  /// As the collection gives it, e.g. "ca. 1600".
  final String? date;

  /// Country or culture of origin.
  final String? origin;

  /// Where it's from, e.g. "The Met · Public domain".
  final String credit;

  /// The collection's page for the work.
  final String? pageUrl;

  const Artwork({
    required this.imageUrl,
    this.fullUrl,
    required this.title,
    this.artist,
    this.date,
    this.origin,
    required this.credit,
    this.pageUrl,
  });

  /// "Title — Artist", for captions and file names.
  String get label => artist == null || artist!.isEmpty ? title : '$title — $artist';

  Map<String, dynamic> toJson() => {
        'imageUrl': imageUrl,
        'fullUrl': fullUrl,
        'title': title,
        'artist': artist,
        'date': date,
        'origin': origin,
        'credit': credit,
        'pageUrl': pageUrl,
      };

  factory Artwork.fromJson(Map<String, dynamic> j) => Artwork(
        imageUrl: j['imageUrl'] as String,
        fullUrl: j['fullUrl'] as String?,
        title: j['title'] as String,
        artist: j['artist'] as String?,
        date: j['date'] as String?,
        origin: j['origin'] as String?,
        credit: j['credit'] as String,
        pageUrl: j['pageUrl'] as String?,
      );
}
