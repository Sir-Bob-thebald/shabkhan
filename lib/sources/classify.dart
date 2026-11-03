import '../models/reading.dart';

final _poemWords = RegExp(r'\b(poems?|poetry|verse|haiku|sonnets?|ghazal)\b|شعر|سروده|غزل|رباعی', caseSensitive: false);
final _storyWords = RegExp(
    r'\b(fiction|short stor(y|ies)|flash fiction|a story|tale|fable|chapter \d+|part \d+ of)\b|داستان|قصه|حکایت',
    caseSensitive: false);
final _dialogueStart = RegExp('^\\s*[“"«‘—–]');
final _speech = RegExp(r'\b(said|asked|replied|whispered|shouted|muttered)\b|گفت|پرسید', caseSensitive: false);

/// Guesses whether a piece is a short story, a poem or an essay, for sources
/// that mix all three (Substack newsletters, literary magazines).
///
/// Labels written by the author (tags, section, title) win; otherwise the
/// text's shape decides: short broken lines read as verse, dialogue and
/// speech verbs as fiction, and anything else as an essay.
ReadingType classify({String title = '', String? subtitle, List<String> tags = const [], String? section, required String text}) {
  final labels = [...tags, ?section].join(' | ');
  if (_poemWords.hasMatch(labels)) return ReadingType.poem;
  if (_storyWords.hasMatch(labels)) return ReadingType.story;

  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (lines.length >= 4 && words < 1500) {
    final short = lines.where((l) => l.length <= 60).length;
    if (short / lines.length >= 0.75) return ReadingType.poem;
  }

  final head = '$title ${subtitle ?? ''}';
  if (_poemWords.hasMatch(head) && words < 1500) return ReadingType.poem;
  if (_storyWords.hasMatch(head)) return ReadingType.story;

  final paragraphs = text.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).toList();
  if (paragraphs.length >= 6) {
    final dialogue = paragraphs.where((p) => _dialogueStart.hasMatch(p)).length;
    final speech = _speech.allMatches(text).length * 1000 / words.clamp(1, 1 << 30);
    if (dialogue / paragraphs.length >= 0.2 || speech >= 4) return ReadingType.story;
  }
  return ReadingType.essay;
}
