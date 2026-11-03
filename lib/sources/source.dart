import 'dart:math';

import '../models/languages.dart';
import '../models/reading.dart';

/// Anything that can produce a reading of one type.
abstract class ReadingSource {
  /// Stable id, used for persisting the on/off switch.
  String get id;
  String get name;
  String get description;
  ReadingType get type;

  /// A language code, or 'auto' (detected from the text).
  String get lang;

  /// The languages its readings come in, where known.
  Set<String> get langs => lang == 'auto' ? const {} : {lang};

  /// Whether some of its readings are in a language not known yet; such
  /// sources are tried for any language and learn it as they go.
  bool get unknownLang => langs.isEmpty;

  /// Built-in sources cannot be deleted, only switched off.
  bool get builtIn => true;

  /// Fetches one reading. Throws [SourceException] when nothing usable came back.
  Future<Reading> fetch(Random rng);

  /// The types this source can supply. Most supply only [type]; mixed
  /// sources (Substack follows, feeds set to "by content") supply several.
  Set<ReadingType> get types => {type};

  /// Fetches one reading of type [want], in language [lang] if the source has
  /// several. Single-type, single-language sources just [fetch].
  Future<Reading> fetchFor(ReadingType want, Random rng, {String? lang}) => fetch(rng);
}

/// The text's language code; see [detectLanguage].
String detectLang(String text) => detectLanguage(text);

T pick<T>(List<T> items, Random rng) => items[rng.nextInt(items.length)];
