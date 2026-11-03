import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightly_reader/main.dart';
import 'package:nightly_reader/models/reading.dart';
import 'package:nightly_reader/services/library.dart';
import 'package:shared_preferences/shared_preferences.dart';

Reading _reading(ReadingType type, String title, String lang, String body) => Reading(
      type: type,
      title: title,
      author: 'Someone',
      body: body,
      sourceId: 'test',
      sourceName: 'Test source',
      url: 'https://example.com/$title',
      lang: lang,
    );

void main() {
  testWidgets('tonight shows all three readings, and one can be read and marked done', (tester) async {
    final night = Night(Library.nightKey(), {
      ReadingType.story: _reading(ReadingType.story, 'The Lantern', 'en', 'Once upon a time.\n\nThe end.'),
      ReadingType.poem: _reading(ReadingType.poem, 'رباعی', 'fa', 'گویند رها کنش که یاری بدخوست\nخوبیش نیرزد به درشتی که دروست'),
      ReadingType.essay: _reading(ReadingType.essay, 'On Slowness', 'en', 'Reading slowly is a pleasure.'),
    });
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'night:${night.date}': jsonEncode(night.toJson()),
      'nights': [night.date],
    });
    final library = await Library.load();

    await tester.pumpWidget(NightlyReaderApp(library: library));
    await tester.pumpAndSettle();

    expect(find.text('0 of 3 read tonight'), findsOneWidget);
    expect(find.text('The Lantern'), findsOneWidget);
    expect(find.text('رباعی'), findsOneWidget);
    expect(find.text('On Slowness'), findsOneWidget);

    // Open the Persian poem: it should be laid out right-to-left.
    await tester.tap(find.text('رباعی'));
    await tester.pumpAndSettle();
    final dir = tester.widget<Directionality>(find
        .ancestor(of: find.textContaining('گویند رها کنش'), matching: find.byType(Directionality))
        .first);
    expect(dir.textDirection, TextDirection.rtl);

    await tester.scrollUntilVisible(find.text('Mark as read'), 200);
    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 read tonight'), findsOneWidget);
    expect(library.nightFor(night.date)!.finished, {ReadingType.poem});
  });

  testWidgets('sources tab lists built-in sources for every type', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final library = await Library.load();
    // Skip network fetches: pretend tonight is already filled.
    for (final t in ReadingType.values) {
      library.tonight.readings[t] = _reading(t, t.label, 'en', 'x');
    }
    await tester.pumpWidget(NightlyReaderApp(library: library));
    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();

    // Stories tab: only story sources, each with its chance.
    expect(find.text('Golestan · گلستان سعدی'), findsOneWidget);
    expect(find.text('PoetryDB'), findsNothing);
    // Two Persian and one English story source: half the nights in each language.
    expect(find.text('25%'), findsNWidgets(2));
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Browse sources'), findsOneWidget);
    expect(find.text('Add by link'), findsOneWidget);
    final golestanRow = find.ancestor(of: find.text('Golestan · گلستان سعدی'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: golestanRow, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    final golestan = library.sources.firstWhere((s) => s.id == 'ganjoor-golestan');
    expect(library.isEnabled(golestan), isFalse);
    expect(find.text('50%'), findsNWidgets(2));

    // Adding from the catalog puts a source on the Poems tab.
    await tester.tap(find.text('Poems'));
    await tester.pumpAndSettle();
    expect(find.text('Hafez · حافظ'), findsNothing);
    await tester.tap(find.text('Browse sources'));
    await tester.pumpAndSettle();
    final hafezRow = find.ancestor(of: find.text('Hafez · حافظ'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: hafezRow, matching: find.byIcon(Icons.add)));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Hafez · حافظ'), findsOneWidget);

    // The source sheet's slider changes how often it comes up.
    await tester.tap(find.text('Hafez · حافظ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('How often, among poems'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await tester.pumpAndSettle();
    final hafez = library.sources.firstWhere((s) => s.id == 'ganjoor-hafez');
    expect(library.weight(hafez, ReadingType.poem), Library.maxWeight);
  });

  testWidgets('the Accounts tab connects Substack with a username, no password', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final library = await Library.load();
    for (final t in ReadingType.values) {
      library.tonight.readings[t] = _reading(t, t.label, 'en', 'x');
    }
    await tester.pumpWidget(NightlyReaderApp(library: library));
    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '@username or profile link'), findsOneWidget);
    expect(find.textContaining('no password is needed'), findsOneWidget);
    expect(find.text('Use an integration secret'), findsOneWidget);
  });
}
