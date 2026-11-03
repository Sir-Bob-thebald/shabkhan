# شبخوان · Nightly Reader

Every night: one short story, one poem and one essay, in Persian, English and
any other language your sources bring.

The app is called **شبخوان** in Persian and **Nightly Reader** in English.
Android picks the name to match the phone's language (`res/values-fa/strings.xml`).
The logo is `assets/logo.png`. To rebuild every launcher icon from the
original artwork, run `py tool/make_icons.py assets/brand/logo_source.png`
(it needs Pillow).

- The three readings stay fixed for the whole night; a new set arrives after 4 am.
- 🔀 on a card swaps that reading for another.
- Mark readings as finished, bookmark favourites, browse past nights.
- Optional nightly reminder notification (Android/iOS).
- Persian text is shown right-to-left automatically.
- Themes in Settings: **Dark** (the default: black with the lamp's warm light),
  **Midnight** (deep blue), **Sepia** and **White**.
- A public-domain **work of art** goes with each reading (see below).

## Sources

**Sources** has a tab per type (Stories, Poems, Essays) plus **Accounts**.
Each type tab lists only what can supply that type, with each source's
**chance** of being picked first. Tap a source for a **How often** slider
(1–10, per type): a source's chance is its weight divided by the total for the
switched-on sources, so a site with a huge collection doesn't win more often.
**Even out** resets a tab to equal chances. Picks use a weighted random
order, so the other sources still act as fallbacks.

A fresh install starts with a short list (\* below). **Browse sources** opens
the catalog, filtered by type and language, where one tap adds a source:

| Type  | Persian | English |
|-------|---------|---------|
| Story | Golestan\*, Kelileh va Demneh\*, Baharestan, Chahar Maqala, Tazkirat al-Awliya | Wikisource\*, Every Day Fiction, SmokeLong, Clarkesworld, Strange Horizons |
| Poem  | Ganjoor (all)\*, Hafez, Saadi, Rumi, Khayyam, Baba Taher, Parvin, Shahriar, Rahi | PoetryDB\*, Wikisource poems, Strange Horizons |
| Essay | Qabus-nameh\*, Akhlaq al-Ashraf\*, Tarjomaan | LessWrong\*, Paul Graham\*, Psyche, Aeon, The Marginalian, Nautilus, Quanta |

German and French come from Wikisource:

| Type  | Deutsch | Français |
|-------|---------|----------|
| Story | Märchen, Erzählungen | Nouvelles, Contes |
| Poem  | Gedichte | Poésie |
| Essay | Essays | Essais |

The catalog is `lib/sources/registry.dart`. `flutter test test/sources_live_test.dart`
checks every entry for every type it supplies.

**Add by link** takes any link: a feed, a blog, a magazine's homepage. The
app finds the feed, either from the page's `<link rel=alternate>` or at a
usual address such as `/feed` or `/rss.xml`. If there isn't one, it reads the
site's article links instead. On Android you can also **share** a link to the
app from the browser (Share → Nightly Reader), which opens the same dialog.
Entries can count as one fixed type,
or be sorted **By content** into story, poem or essay by
`lib/sources/classify.dart`. That uses the author's tags or section first;
failing that, short broken lines make a poem, dialogue and speech verbs make a
story, and anything else is an essay. Entries under 300 words (20 for poems)
or over 8,000 are skipped. If a feed only carries teasers, the app fetches the
linked page.

### Languages

**Settings → Languages** has a slider (0–100) for every language your
switched-on sources come in, including the ones your own feeds and Substacks
bring. The values are relative: Russian 50, German 25 and French 25 puts half
the nights in Russian, and 0 means never. Each night picks a language first by
these weights, then a source in that language by its own chance. The share
shown is among all your languages; a type only uses the languages it has
sources in.

A source's language comes from:
- the catalog;
- a feed's `<language>` tag, or detection from its entries when you add it
  (you can change it in the feed's sheet);
- for Substack and Notion, each publication's or row's own language, learned
  as posts are read.

`lib/models/languages.dart` detects about 20 languages by script and common
words, with no network calls.

### Artwork

Each reading gets a public-domain painting or other work, found by
`lib/services/art_finder.dart` in three steps of importance:

1. **Subject**: picture motifs such as night, moon, garden, king, sea or
   lovers, recognised from the text's words in about ten languages.
2. **Place of origin**: from the reading's language (Persian → Iran,
   German → Germany…).
3. **Era**: from the source or author (Hafez → 1350–1550, Wikisource
   classics → 1780–1920).

It asks **The Met**'s open-access API first (filtering by `geoLocation` and
`dateBegin`/`dateEnd`). Each search keeps the subject; the era, then the
place, are dropped when nothing matches. **Wikimedia Commons** is the
fallback, using public-domain files only. The Art Institute of Chicago's API
is behind a Cloudflare check from Iran, so it isn't used.

Pictures appear as a faint backdrop on the Tonight card and at the top of
the reader, with title, artist, date, origin and credit. They are left out
entirely when offline. Tap ♡ to like one; a liked picture can be
**downloaded**, named "Title — Artist (date)": into the phone's gallery
(album "Nightly Reader"), or into Downloads on a computer. **Substack**
readings use the post's own cover image instead. Settings can turn artwork off.

### Translation

The reader's **Translate** button uses machine translation, not an AI model,
and its result is cached. "Machine-translated from … into …" is shown above
the text, and the same button brings back the original. To translate a source
every time, set **Always translate into** in its sheet. **Settings →
Translation** sets the target language and the service:

- **Google Translate**: the free web endpoint (`translate.googleapis.com`,
  `client=gtx`). It's unofficial but needs no key, takes about 3,500
  characters per request, and works from Iran without a VPN (tested).
- **MyMemory**: an official free API, but limited to 500 characters per
  request and about 5,000 a day, so it suits short texts only.
- **LibreTranslate**: open source; give the server URL and a key if it needs one.

### Substack

**Accounts → Substack**: type your username (`@name` or a profile link). The
app reads the publications you follow from your **public profile**
(`substack.com/api/v1/user/<name>/public_profile`), so there's no password or
sign-in. Your subscriptions must be visible on your profile (a Substack setting).
Each publication is **By content** by default, meaning each post is sorted by
`classify` and the verdict remembered. You can also pin a publication to one
type or switch it off. Together the publications count as **one source**, so
following many doesn't crowd out the others.

**Paid posts (optional)**: sign in on Substack's page inside the app. It now
runs with a desktop user agent and blocks links to the Substack app, the Play
Store and `intent://`, so it no longer hands off to the app. If the emailed
link opens the Substack app, copy it and paste it into the field under the
page. The session is kept in secure storage and only sent to substack.com.

### Notion: Reading Atlas

The app reads from the **Sources** database that `notion/atlas.py` built
(the Reading Atlas: your Chrome tab groups and OneTab links). It uses
**only the rows ticked `Nightly read`**, and skips rows whose Status is Skip, Read
or Synthesized.

`Nightly read` (plus a `Words` number) is set by `tool/atlas_nightly.dart`.
It checks every row whose type can hold a text (articles, Wikipedia and other
encyclopedia entries, texts, scholarship, posts) and fetches the page with the
app's own extractor. A row is ticked only if the page is:

- reachable from here (not 403/404, not a PDF or other file);
- **300–4,000 words** (about 2–20 minutes);
- prose: at least 3 paragraphs of real length, and not a list, index or home page;
- not from a site that only carries ads, shops, jobs, admissions, forums,
  profiles or game lore (`blockedHosts`, chosen by reviewing the scan).

```powershell
$env:ATLAS_DB = "<Sources database ID or link>"   # plus NOTION_TOKEN
dart run tool/atlas_nightly.dart scan     # measure pages (resumable; run twice to retry network failures)
dart run tool/atlas_nightly.dart report -v
dart run tool/atlas_nightly.dart push     # write Nightly read + Words to Notion
```

You can tick or clear `Nightly read` by hand in Notion: `push` remembers what
it last wrote (in `tool/atlas_scan.json`) and leaves rows you changed alone.
Run `scan` + `push` again after importing new tabs with `atlas.py push`.

When you finish a reading in the app, its Status becomes **Read**, so it drops
out of the pool. You can turn this off in Sources.

**Accounts → Notion**. The database is found by its `Nightly read` checkbox
(through Notion's search API), so there's no database ID to type, and none is
built into the app. There are two ways to connect:

- **Connect with Notion** (OAuth): you sign in on Notion's page in the phone's
  browser (Google sign-in works there) and pick the pages to share. Notion only
  accepts `https://` redirect URIs, so it sends the browser to a static page,
  `https://sir-bob-thebald.github.io/shabkhan-oauth/notion/` (source in
  `tool/oauth_page/`). That page passes `code` and `state` on to
  `shabkhan://oauth/notion`, and Android hands the link to the app. The app
  checks the `state` it saved when starting, then swaps the code for a token.
  The page sees only the code, which is useless without the client secret.
  This needs:
  1. The page published: a **public** repo `shabkhan-oauth` holding
     `tool/oauth_page/` at its root, with GitHub Pages on (branch `main`, folder `/`).
  2. A *public* Notion integration (notion.so/profile/integrations → New
     integration → Public) whose redirect URI is exactly that page's address.
  3. Its credentials in `notion_oauth.json` (git-ignored):
  ```json
  {"NOTION_CLIENT_ID": "…", "NOTION_CLIENT_SECRET": "…"}
  ```
     Then build with `--dart-define-from-file=notion_oauth.json`. The button only
  appears in builds that have them. The secret ends up in the APK but not in
  the source code, which is acceptable for a personal sideloaded app.
- **Use an integration secret**: paste `NOTION_TOKEN` from `notion/.env`.

The token is kept in secure storage and only sent to api.notion.com. The row
list is cached for 12 hours, and the cached copy is used when Notion can't be
reached. Calls are retried, since TLS handshakes to Notion often drop on this
network. The code is in `lib/services/notion_account.dart` and
`lib/sources/notion_atlas.dart`.

New ready-made sources go in `lib/sources/` (implement `ReadingSource`, and
override `types`/`fetchFor` for mixed ones) and are added to the catalog in
`lib/sources/registry.dart`.

## Running

The SDK lives at `%USERPROFILE%\dev\flutter_sdk`. Google's Flutter servers
return 403 from this network, so set the mirror first (PowerShell):

```powershell
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$flutter = "$env:USERPROFILE\dev\flutter_sdk\bin\flutter.bat"

& $flutter pub get
& $flutter analyze
& $flutter test --exclude-tags live           # offline tests
& $flutter test test/sources_live_test.dart   # real sources (set NOTION_TOKEN for the atlas test)

# Android (arm64 only; see PROGRESS.md for the Gradle mirror and engine-jar setup)
& $flutter build apk --debug --target-platform android-arm64
& $flutter run --target-platform android-arm64
```

For "Connect with Notion", add
`--dart-define=NOTION_CLIENT_ID=… --dart-define=NOTION_CLIENT_SECRET=…` to the
build or run command.

The web build is only for previews: browsers block LessWrong, Wikisource and
most feeds.
