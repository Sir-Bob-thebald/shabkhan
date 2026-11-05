# شبخوان · Nightly Reader

<img src="assets/logo.png" width="96" align="right" alt="Nightly Reader logo">

A calm bedtime reading app: every night it offers **one short story, one poem
and one essay**, drawn from sources you choose, in Persian, English and other
languages.

Built with Flutter, Android first.

## Features

- **A fresh trio every night**: the readings stay the same all night, and a
  new set arrives in the morning. Don't like one? Swap it for another.
- **Sources you control**: classic literature, poetry collections, essay sites
  and magazines, or any blog or feed you add by link. You set how often each
  one is picked.
- **Many languages**: Persian, English, German, French and more, with your
  own mix of languages per night. Right-to-left text is handled
  automatically.
- **Newsletters and notes**: you can bring in Substack publications you follow
  and a Notion reading list.
- **Artwork**: each reading comes with a public-domain painting from open
  museum collections, chosen to suit the text.
- **Built-in translation** for readings in languages you don't read.
- **Reading history**: mark readings as finished, bookmark favourites and
  browse past nights.
- **Themes**: Dark, Midnight, Sepia and White.
- **Optional nightly reminder** notification.

## Download

**[Download the latest Android APK](https://github.com/Sir-Bob-thebald/shabkhan/releases/latest/download/shabkhan-nightly-reader-arm64.apk)**
(Android, 64-bit ARM, about 22 MB). Older versions are on the
[Releases](https://github.com/Sir-Bob-thebald/shabkhan/releases) page.

To install it, open the file on your phone and allow installing from this
source when Android asks.

## Building from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
flutter pub get
flutter run
```

Run the tests with `flutter test --exclude-tags live`.

## Project layout

```
lib/
  models/     data types (readings, languages)
  sources/    one file per content provider, plus the source catalog
  services/   app state, accounts, artwork, translation, reminders
  screens/    the UI
test/         unit tests and live source checks
tool/         helper scripts (icons, OAuth redirect page)
```

To add a new source, implement `ReadingSource` in `lib/sources/` and register
it in `lib/sources/registry.dart`.
