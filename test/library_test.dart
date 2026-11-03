import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightly_reader/models/reading.dart';
import 'package:nightly_reader/services/library.dart';
import 'package:nightly_reader/services/net.dart';
import 'package:nightly_reader/sources/source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the night rolls over at 4 am, not midnight', () {
    expect(Library.nightKey(DateTime(2026, 11, 3, 23, 0)), '2026-11-03');
    expect(Library.nightKey(DateTime(2026, 11, 4, 1, 30)), '2026-11-03');
    expect(Library.nightKey(DateTime(2026, 11, 4, 4, 1)), '2026-11-04');
  });

  test('language detection tells Persian from English', () {
    expect(detectLang('گویند رها کنش که یاری بدخوست'), 'fa');
    expect(detectLang('The fog comes on little cat feet.'), 'en');
  });

  test('htmlToText keeps paragraphs and line breaks', () {
    expect(htmlToText('<p>One <b>two</b></p><p>Three<br>four</p>'), 'One two\n\nThree\nfour');
    // Newlines in the HTML source are not line breaks.
    expect(htmlToText('Here is\nwrapped text.<br><br>Next'), 'Here is wrapped text.\n\nNext');
  });

  test('a night survives a save/load round trip', () {
    final r = Reading(
      type: ReadingType.poem,
      title: 'T',
      body: 'line one\nline two',
      sourceId: 's',
      sourceName: 'S',
      url: 'https://x',
      lang: 'fa',
    );
    final n = Night('2026-11-03', {ReadingType.poem: r}, {ReadingType.poem});
    final back = Night.fromJson(n.toJson());
    expect(back.readings[ReadingType.poem]!.body, r.body);
    expect(back.finished, {ReadingType.poem});
    expect(back.readings[ReadingType.poem]!.isRtl, isTrue);
  });

  test('switching a source off is remembered', () async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final lib = await Library.load();
    final first = lib.sources.first;
    await lib.setEnabled(first, false);
    final reloaded = await Library.load();
    expect(reloaded.isEnabled(reloaded.sources.first), isFalse);
  });

  test('mainText follows sectioned articles and keeps headings that have text', () {
    const page = '<html><body><nav><p>Menu menu menu</p></nav><div class="mw-parser-output">'
        '<section><p>Lead paragraph.</p></section>'
        '<section><div class="mw-heading"><h2>History</h2><span>[edit]</span></div><p>First part.</p><p>Second part.</p></section>'
        '<section><div class="mw-heading"><h2>References</h2></div><ol><li>Ref</li></ol></section>'
        '</div></body></html>';
    expect(mainText(page), 'Lead paragraph.\n\nHistory\n\nFirst part.\n\nSecond part.');
  });
}
