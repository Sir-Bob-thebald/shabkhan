import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
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
    final res = await Net.client.get(Uri.parse(a.fullUrl ?? a.imageUrl)).timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) throw SourceException('Could not download the image (HTTP ${res.statusCode})');
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
