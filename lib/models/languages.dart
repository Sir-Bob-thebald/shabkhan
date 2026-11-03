/// A language the app knows how to name, lay out and detect.
class Language {
  final String code; // ISO 639-1
  final String name; // in English
  final String native;
  final bool rtl;
  const Language(this.code, this.name, this.native, {this.rtl = false});

  /// e.g. "Русский · Russian"; just the name when they're the same.
  String get label => native == name ? name : '$native · $name';
}

const languages = <String, Language>{
  'fa': Language('fa', 'Persian', 'فارسی', rtl: true),
  'en': Language('en', 'English', 'English'),
  'ar': Language('ar', 'Arabic', 'العربية', rtl: true),
  'ur': Language('ur', 'Urdu', 'اردو', rtl: true),
  'he': Language('he', 'Hebrew', 'עברית', rtl: true),
  'ru': Language('ru', 'Russian', 'Русский'),
  'uk': Language('uk', 'Ukrainian', 'Українська'),
  'de': Language('de', 'German', 'Deutsch'),
  'fr': Language('fr', 'French', 'Français'),
  'es': Language('es', 'Spanish', 'Español'),
  'it': Language('it', 'Italian', 'Italiano'),
  'pt': Language('pt', 'Portuguese', 'Português'),
  'nl': Language('nl', 'Dutch', 'Nederlands'),
  'sv': Language('sv', 'Swedish', 'Svenska'),
  'pl': Language('pl', 'Polish', 'Polski'),
  'tr': Language('tr', 'Turkish', 'Türkçe'),
  'el': Language('el', 'Greek', 'Ελληνικά'),
  'hi': Language('hi', 'Hindi', 'हिन्दी'),
  'zh': Language('zh', 'Chinese', '中文'),
  'ja': Language('ja', 'Japanese', '日本語'),
  'ko': Language('ko', 'Korean', '한국어'),
  'hy': Language('hy', 'Armenian', 'Հայերեն'),
  'ka': Language('ka', 'Georgian', 'ქართული'),
};

Language languageOf(String code) => languages[code] ?? Language(code, code.toUpperCase(), code.toUpperCase());

bool isRtlLang(String code) => languages[code]?.rtl ?? false;

/// Turns `en-US`, `ru_RU` or `EN` into `en`; null when it isn't a code.
String? normalizeLang(String? tag) {
  final m = RegExp(r'^([a-zA-Z]{2,3})(?:[-_].*)?$').firstMatch(tag?.trim() ?? '');
  return m?.group(1)!.toLowerCase();
}

// Common short words that tell Latin-script languages apart.
const _stopwords = <String, List<String>>{
  'en': ['the', 'and', 'of', 'to', 'is', 'that', 'it', 'was', 'with', 'for', 'you', 'this', 'not', 'but', 'have'],
  'de': ['der', 'die', 'und', 'das', 'ist', 'nicht', 'ich', 'mit', 'sich', 'auf', 'ein', 'eine', 'auch', 'dem', 'den'],
  'fr': ['le', 'la', 'les', 'et', 'est', 'des', 'une', 'que', 'qui', 'pas', 'dans', 'pour', 'sur', 'avec', 'il'],
  'es': ['el', 'la', 'los', 'las', 'y', 'que', 'es', 'una', 'por', 'con', 'para', 'del', 'como', 'pero', 'su'],
  'it': ['il', 'di', 'che', 'e', 'la', 'non', 'per', 'una', 'sono', 'gli', 'con', 'del', 'della', 'anche', 'è'],
  'pt': ['o', 'a', 'que', 'de', 'não', 'uma', 'os', 'em', 'com', 'para', 'do', 'da', 'mas', 'é', 'se'],
  'nl': ['de', 'het', 'een', 'en', 'van', 'dat', 'niet', 'is', 'zijn', 'ik', 'op', 'te', 'met', 'voor', 'maar'],
  'sv': ['och', 'att', 'det', 'som', 'en', 'är', 'på', 'för', 'med', 'inte', 'jag', 'av', 'till', 'den', 'har'],
  'pl': ['i', 'w', 'nie', 'się', 'na', 'jest', 'że', 'to', 'z', 'do', 'jak', 'co', 'ale', 'tak', 'po'],
  'tr': ['ve', 'bir', 'bu', 'da', 'de', 'için', 'ne', 'çok', 'gibi', 'ile', 'daha', 'ama', 'olarak', 'değil', 'ben'],
};

/// Guesses a text's language from its script and, for Latin script, its
/// common words. Good enough to group sources; returns 'en' when unsure.
String detectLanguage(String text) {
  final sample = text.length > 3000 ? text.substring(0, 3000) : text;
  final counts = <String, int>{};
  void add(String k) => counts[k] = (counts[k] ?? 0) + 1;
  var persian = 0, arabic = 0, urdu = 0, ukrainian = 0, kana = 0;
  for (final r in sample.runes) {
    if (r >= 0x0600 && r <= 0x06FF || r >= 0xFB50 && r <= 0xFEFF) {
      add('arab');
      if (r == 0x067E || r == 0x0686 || r == 0x0698 || r == 0x06AF || r == 0x06CC || r == 0x06A9) persian++;
      if (r == 0x0629 || r == 0x064A || r == 0x0643 || r == 0x0649) arabic++;
      if (r == 0x0679 || r == 0x0688 || r == 0x0691 || r == 0x06BA || r == 0x06D2) urdu++;
    } else if (r >= 0x0400 && r <= 0x04FF) {
      add('cyr');
      if (r == 0x0456 || r == 0x0457 || r == 0x0454 || r == 0x0491) ukrainian++;
    } else if (r >= 0x0370 && r <= 0x03FF) {
      add('el');
    } else if (r >= 0x0590 && r <= 0x05FF) {
      add('he');
    } else if (r >= 0x0900 && r <= 0x097F) {
      add('hi');
    } else if (r >= 0x0530 && r <= 0x058F) {
      add('hy');
    } else if (r >= 0x10A0 && r <= 0x10FF) {
      add('ka');
    } else if (r >= 0xAC00 && r <= 0xD7AF) {
      add('ko');
    } else if (r >= 0x3040 && r <= 0x30FF) {
      kana++;
      add('cjk');
    } else if (r >= 0x4E00 && r <= 0x9FFF) {
      add('cjk');
    } else if (r >= 0x41 && r <= 0x7A || r >= 0xC0 && r <= 0x24F) {
      add('lat');
    }
  }
  if (counts.isEmpty) return 'en';
  final script = (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  switch (script) {
    case 'arab':
      if (urdu > persian && urdu > 0) return 'ur';
      return arabic > persian ? 'ar' : 'fa';
    case 'cyr':
      return ukrainian > 2 ? 'uk' : 'ru';
    case 'cjk':
      return kana > 0 ? 'ja' : 'zh';
    case 'lat':
      final words = sample.toLowerCase().split(RegExp(r"[^a-zà-ɏ']+")).where((w) => w.isNotEmpty);
      final score = {for (final l in _stopwords.keys) l: 0};
      for (final w in words) {
        for (final e in _stopwords.entries) {
          if (e.value.contains(w)) score[e.key] = score[e.key]! + 1;
        }
      }
      final best = (score.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;
      return best.value == 0 ? 'en' : best.key;
    default:
      return script;
  }
}
