import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/artwork.dart';
import 'net.dart';

/// Saves a liked artwork, named "Title — Artist (date)": to the phone's
/// gallery (album "Nightly Reader"), or to Downloads on a computer.
class ArtSaver {
  static const album = 'Nightly Reader';

  /// A file name from the work's title, artist and date, without characters
  /// that file systems refuse.
  static String fileName(Artwork a) {
    final base = [a.label, if (a.date != null) '(${a.date})'].join(' ');
    final clean = base.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > 120 ? clean.substring(0, 120).trim() : clean;
  }

  /// Returns where it went, for a message to the user.
  static Future<String> save(Artwork a) async {
    Future<http.Response> get(String url) => Net.client.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
    bool isImage(http.Response r) => r.statusCode == 200 && (r.headers['content-type'] ?? 'image/').startsWith('image/');
    var res = await get(a.fullUrl ?? a.imageUrl);
    // Some full-size servers refuse this network, or answer with an HTML
    // error page; the screen-sized copy is better than nothing.
    if (!isImage(res) && a.fullUrl != null && a.fullUrl != a.imageUrl) res = await get(a.imageUrl);
    if (!isImage(res)) throw SourceException('Could not download the image (HTTP ${res.statusCode})');
    final bytes = res.bodyBytes;
    final name = fileName(a);
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
        throw SourceException('The app may not save to the gallery; allow it in system settings');
      }
      await Gal.putImageBytes(bytes, album: album, name: name);
      return 'Saved to the gallery, album "$album"';
    }
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final ext = RegExp(r'\.(jpe?g|png|webp|gif)(\?|$)', caseSensitive: false).firstMatch(a.fullUrl ?? a.imageUrl)?.group(1) ?? 'jpg';
    final file = File('${dir.path}${Platform.pathSeparator}$name.$ext');
    await file.writeAsBytes(bytes);
    return 'Saved to ${file.path}';
  }
}
