import 'dart:convert';

import 'net.dart';

/// Machine translation services (no LLM involved).
enum TranslatorKind {
  /// Google Translate's free web endpoint (the one browser extensions use).
  /// Unofficial: no key, no fixed quota, but it may change or rate-limit.
  google('Google Translate', 'Free web endpoint; works without a VPN here'),

  /// MyMemory: free, official API, but 500 characters per request and about
  /// 5,000 per day, so only short poems really fit.
  myMemory('MyMemory', '≈5,000 characters a day for free'),

  /// A LibreTranslate server (open source; e.g. one you run yourself).
  libre('LibreTranslate', 'Your own or a hosted server (URL, optional key)');

  final String label;
  final String blurb;
  const TranslatorKind(this.label, this.blurb);
}

class Translator {
  final TranslatorKind kind;
  final String? libreUrl;
  final String? libreKey;

  const Translator(this.kind, {this.libreUrl, this.libreKey});

  int get _chunk => kind == TranslatorKind.myMemory ? 480 : 3500;

  /// Translates [text] from [from] into [to], keeping paragraph breaks.
  Future<String> translate(String text, {required String from, required String to}) async {
    if (text.trim().isEmpty || from == to) return text;
    final out = <String>[];
    for (final chunk in chunks(text, _chunk)) {
      out.add((await _one(chunk, from, to)).trim());
    }
    return out.join('\n\n');
  }

  /// Splits on paragraphs, then lines, then sentences, so no piece is over [max].
  static List<String> chunks(String text, int max) {
    final pieces = <String>[];
    void addPiece(String p) {
      if (p.length <= max) return pieces.add(p);
      final parts = p.contains('\n') ? p.split('\n') : p.split(RegExp(r'(?<=[.!?؟。])\s+'));
      if (parts.length == 1) {
        for (var i = 0; i < p.length; i += max) {
          pieces.add(p.substring(i, i + max > p.length ? p.length : i + max));
        }
        return;
      }
      var buf = '';
      for (final s in parts) {
        if (buf.isNotEmpty && buf.length + s.length + 1 > max) {
          addPiece(buf);
          buf = '';
        }
        buf = buf.isEmpty ? s : '$buf${p.contains('\n') ? '\n' : ' '}$s';
      }
      if (buf.isNotEmpty) addPiece(buf);
    }

    var group = '';
    for (final para in text.split(RegExp(r'\n\s*\n'))) {
      if (group.isNotEmpty && group.length + para.length + 2 > max) {
        addPiece(group);
        group = '';
      }
      group = group.isEmpty ? para : '$group\n\n$para';
    }
    if (group.isNotEmpty) addPiece(group);
    return pieces;
  }

  static String _googleCode(String c) => switch (c) { 'zh' => 'zh-CN', 'he' => 'iw', _ => c };

  Future<String> _one(String text, String from, String to) async {
    switch (kind) {
      case TranslatorKind.google:
        final res = await Net.client.post(
          Uri.https('translate.googleapis.com', '/translate_a/single',
              {'client': 'gtx', 'sl': _googleCode(from), 'tl': _googleCode(to), 'dt': 't'}),
          headers: {'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8'},
          body: 'q=${Uri.encodeQueryComponent(text)}',
        ).timeout(const Duration(seconds: 30));
        if (res.statusCode == 429) throw RateLimitedException('Google Translate');
        if (res.statusCode != 200) throw SourceException('Google Translate: HTTP ${res.statusCode}');
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as List;
        return [for (final seg in (data[0] as List? ?? const [])) (seg as List)[0] ?? ''].join();
      case TranslatorKind.myMemory:
        final data = await Net.getJson(Uri.https('api.mymemory.translated.net', '/get', {
          'q': text,
          'langpair': '$from|$to',
        }).toString()) as Map;
        if (data['responseStatus'] != 200 || data['quotaFinished'] == true) {
          throw SourceException('MyMemory: ${data['responseDetails'] ?? 'quota used up for today'}');
        }
        return (data['responseData'] as Map)['translatedText'] as String;
      case TranslatorKind.libre:
        final base = (libreUrl ?? '').replaceFirst(RegExp(r'/+$'), '');
        if (base.isEmpty) throw SourceException('Set your LibreTranslate server in Settings');
        final data = await Net.postJson('$base/translate', {
          'q': text,
          'source': from,
          'target': to,
          'format': 'text',
          if (libreKey?.isNotEmpty == true) 'api_key': libreKey,
        }) as Map;
        final t = data['translatedText'] as String?;
        if (t == null) throw SourceException('LibreTranslate: ${data['error'] ?? 'no translation'}');
        return t;
    }
  }
}
