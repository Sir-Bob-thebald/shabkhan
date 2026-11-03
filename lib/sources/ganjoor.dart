import 'dart:math';

import '../models/reading.dart';
import '../services/net.dart';
import 'source.dart';

const _api = 'https://api.ganjoor.net/api/ganjoor';
const _site = 'https://ganjoor.net';

/// Builds a [Reading] from a Ganjoor poem/prose JSON object.
Reading _toReading(Map<String, dynamic> poem, ReadingSource src) {
  final parts = (poem['fullTitle'] as String).split('»').map((s) => s.trim()).toList();
  final author = parts.first;
  final title = parts.length > 1 ? parts.sublist(1).join(' — ') : parts.first;
  return Reading(
    type: src.type,
    title: title,
    author: author,
    body: _bodyOf(poem),
    sourceId: src.id,
    sourceName: src.name,
    url: '$_site${poem['fullUrl']}',
    lang: 'fa',
  );
}

/// Lays verses out as couplets separated by blank lines; prose stays as paragraphs.
String _bodyOf(Map<String, dynamic> poem) {
  final verses = (poem['verses'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  if (verses.isEmpty) return tidyText(poem['plainText'] as String? ?? '');
  final buf = StringBuffer();
  int? lastCouplet;
  for (final v in verses) {
    final couplet = v['coupletIndex'] as int?;
    final text = (v['text'] as String? ?? '').trim();
    if (text.isEmpty) continue;
    if (buf.isNotEmpty) buf.write(couplet != null && couplet == lastCouplet ? '\n' : '\n\n');
    buf.write(text);
    lastCouplet = couplet;
  }
  return tidyText(buf.toString());
}

/// A random poem from the whole Ganjoor library, or from one poet when
/// [poetId] is set, kept to a bedtime length.
class GanjoorPoemSource extends ReadingSource {
  @override
  final String id;
  @override
  final String name;
  @override
  final String description;
  final int? poetId;

  GanjoorPoemSource({
    this.id = 'ganjoor-poem',
    this.name = 'Ganjoor · گنجور',
    this.description = 'Random classical Persian poem (ghazals, rubaiyat, qasidas…)',
    this.poetId,
  });

  @override
  ReadingType get type => ReadingType.poem;
  @override
  String get lang => 'fa';

  @override
  Future<Reading> fetch(Random rng) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final poem = await Net.getJson('$_api/poem/random${poetId == null ? '' : '?poetId=$poetId'}') as Map<String, dynamic>;
      // coupletsCount is null on this endpoint, so count from the verses.
      final couplets = ((poem['verses'] as List?) ?? const []).map((v) => (v as Map)['coupletIndex']).toSet().length;
      if (couplets >= 2 && couplets <= 20) return _toReading(poem, this);
    }
    throw SourceException('Ganjoor kept returning very long poems');
  }
}

/// A random section (tale, chapter) from one or more Ganjoor categories.
class GanjoorCategorySource extends ReadingSource {
  @override
  final String id;
  @override
  final String name;
  @override
  final String description;
  @override
  final ReadingType type;
  final List<int> categoryIds;
  final int minChars;
  final int maxChars;

  GanjoorCategorySource({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.categoryIds,
    this.minChars = 300,
    this.maxChars = 30000,
  });

  @override
  String get lang => 'fa';

  @override
  Future<Reading> fetch(Random rng) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      final catId = pick(categoryIds, rng);
      final cat = (await Net.getJson('$_api/cat/$catId?poems=true') as Map)['cat'] as Map;
      final poems = (cat['poems'] as List? ?? const []).cast<Map>();
      if (poems.isEmpty) continue;
      final id = pick(poems, rng)['id'];
      final poem = await Net.getJson('$_api/poem/$id') as Map<String, dynamic>;
      final length = (poem['plainText'] as String? ?? '').length;
      if (length >= minChars && length <= maxChars) return _toReading(poem, this);
    }
    throw SourceException('$name: no section of a suitable length');
  }
}
