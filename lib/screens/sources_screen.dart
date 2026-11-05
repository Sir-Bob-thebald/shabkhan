import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/languages.dart';
import '../models/reading.dart';
import '../services/library.dart';
import '../services/notion_account.dart';
import '../sources/feed.dart';
import '../sources/notion_atlas.dart';
import '../sources/source.dart';
import '../sources/substack.dart';
import 'catalog_screen.dart';
import 'notion_login_screen.dart';
import 'package:url_launcher/url_launcher.dart';

import 'substack_login_screen.dart';

/// Sources, one tab per reading type plus the connected accounts. Each type
/// tab lists only what can supply that type, with each source's chance.
class SourcesScreen extends StatelessWidget {
  final Library library;
  const SourcesScreen({super.key, required this.library});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: 'Stories'), Tab(text: 'Poems'), Tab(text: 'Essays'), Tab(text: 'Accounts')]),
          Expanded(
            child: ListenableBuilder(
              listenable: library,
              builder: (context, _) => TabBarView(children: [
                for (final t in ReadingType.values) _TypeTab(library: library, type: t),
                _AccountsTab(library: library),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

String _plural(ReadingType t) => switch (t) {
      ReadingType.story => 'stories',
      ReadingType.poem => 'poems',
      ReadingType.essay => 'essays',
    };

String _percent(double c) => c == 0 ? 'off' : c < 0.01 ? '<1%' : '${(c * 100).round()}%';

class _TypeTab extends StatelessWidget {
  final Library library;
  final ReadingType type;
  const _TypeTab({required this.library, required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = library.sources.where((s) => s.types.contains(type)).toList()
      ..sort((a, b) => library.chance(b, type).compareTo(library.chance(a, type)));
    final uneven = list.any((s) => library.weight(s, type) != Library.defaultWeight);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Each night\'s ${type.label.toLowerCase()} comes from one of these. The percentage is its chance; '
            'tap a source to make it come up more or less often.',
            style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        if (list.isEmpty)
          const ListTile(title: Text('No sources yet'), subtitle: Text('Browse the catalog to add some.')),
        for (final s in list) _SourceRow(library: library, source: s, type: type),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => CatalogScreen(library: library, initialType: type))),
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('Browse sources'),
              ),
              OutlinedButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => _AddFeedDialog(library: library, type: type)),
                icon: const Icon(Icons.rss_feed),
                label: const Text('Add by link'),
              ),
              if (uneven)
                TextButton.icon(
                  onPressed: () => library.evenOut(type),
                  icon: const Icon(Icons.balance),
                  label: const Text('Even out'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LangBadge extends StatelessWidget {
  final ReadingSource source;
  const _LangBadge(this.source);

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (source) {
      SubstackSource() => (null, Icons.mark_email_read_outlined),
      NotionAtlasSource() => (null, Icons.hub_outlined),
      FeedSource() => (null, Icons.rss_feed),
      _ => (source.lang.toUpperCase(), null),
    };
    return CircleAvatar(
      radius: 16,
      child: icon != null ? Icon(icon, size: 16) : Text(label!, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final Library library;
  final ReadingSource source;
  final ReadingType type;
  const _SourceRow({required this.library, required this.source, required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = library.isEnabled(source);
    final chance = library.chance(source, type);
    return ListTile(
      leading: _LangBadge(source),
      title: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(source.description, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: chance, minHeight: 3, backgroundColor: theme.colorScheme.surfaceContainerHighest),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            child: Text(_percent(chance),
                textAlign: TextAlign.end,
                style: theme.textTheme.labelMedium!.copyWith(color: on ? theme.colorScheme.primary : theme.colorScheme.outline)),
          ),
          Switch(value: on, onChanged: (v) => library.setEnabled(source, v)),
        ],
      ),
      onTap: () => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _SourceSheet(library: library, source: source, type: type),
      ),
    );
  }
}

/// Details of one source: how often it comes up, and what to do with it.
class _SourceSheet extends StatelessWidget {
  final Library library;
  final ReadingSource source;
  final ReadingType type;
  const _SourceSheet({required this.library, required this.source, required this.type});

  static String _howOften(int w) => switch (w) {
        <= 2 => 'Rarely',
        <= 4 => 'Less often',
        5 => 'Normal',
        <= 7 => 'More often',
        _ => 'Very often',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        // A source may have been removed while the sheet was open.
        final s = library.sources.where((x) => x.id == source.id).firstOrNull ?? source;
        final w = library.weight(s, type);
        final on = library.isEnabled(s);
        final custom = s is FeedSource && !s.id.startsWith('cat-');
        final account = s is SubstackSource || s is NotionAtlasSource;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(s.description, style: theme.textTheme.bodyMedium!.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text('How often, among ${_plural(type)}', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    Text(on ? _howOften(w) : 'Switched off', style: theme.textTheme.labelLarge),
                  ],
                ),
                Slider(
                  value: w.toDouble(),
                  min: 1,
                  max: Library.maxWeight.toDouble(),
                  divisions: Library.maxWeight - 1,
                  onChanged: on ? (v) => library.setWeight(s, type, v.round()) : null,
                ),
                Text(
                  on
                      ? 'Comes first on about ${_percent(library.chance(s, type))} of nights\' ${_plural(type)}. '
                          'It doesn\'t matter how big its collection is: only this setting and the language '
                          'settings count.'
                      : 'Switch it on to use it.',
                  style: theme.textTheme.bodySmall,
                ),
                if (s.types.length > 1) ...[
                  const SizedBox(height: 8),
                  Text('It also supplies other types; each has its own setting in that tab.',
                      style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline)),
                ],
                if (custom) ...[
                  const SizedBox(height: 20),
                  Text('Its entries count as', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _TypeChoice(value: s.fixedType, onChanged: (t) => library.setFeedType(s, t)),
                  const SizedBox(height: 16),
                  Text('Language', style: theme.textTheme.titleSmall),
                  LanguagePicker(
                    value: s.language,
                    noneLabel: 'Not known yet (learned from the first reading)',
                    onChanged: (c) => c == null ? null : library.setFeedLanguage(s, c),
                  ),
                ] else if (s.langs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('In ${s.langs.map((c) => languageOf(c).name).join(', ')}', style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 16),
                Text('Always translate into', style: theme.textTheme.titleSmall),
                LanguagePicker(
                  value: library.autoTranslate(s.id),
                  noneLabel: 'Off: show the original',
                  onChanged: (c) => library.setAutoTranslate(s, c),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (!account)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          library.removeFromList(s);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(custom ? 'Delete feed' : 'Remove from my sources'),
                      )
                    else
                      Expanded(
                        child: Text('Manage it under Accounts.',
                            style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline)),
                      ),
                    const Spacer(),
                    Switch(value: on, onChanged: (v) => library.setEnabled(s, v)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "By content" plus the three types; null means by content.
class _TypeChoice extends StatelessWidget {
  final ReadingType? value;
  final ValueChanged<ReadingType?> onChanged;
  const _TypeChoice({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ReadingType?>(
      showSelectedIcon: false,
      segments: [
        const ButtonSegment(value: null, label: Text('By content')),
        for (final t in ReadingType.values) ButtonSegment(value: t, label: Text(t.shortLabel)),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

class _AccountsTab extends StatelessWidget {
  final Library library;
  const _AccountsTab({required this.library});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const _SectionTitle('Substack'),
        _SubstackSection(library: library),
        const _SectionTitle('Notion: Reading Atlas'),
        _NotionSection(library: library),
      ],
    );
  }
}

/// Runs [action] with a spinner flag and shows its error, if any, in a snackbar.
mixin _Busy<T extends StatefulWidget> on State<T> {
  bool busy = false;

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      // Everything, not only Exceptions: a silent failure looks like a dead button.
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

const _spinner = SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));

class _SubstackSection extends StatefulWidget {
  final Library library;
  const _SubstackSection({required this.library});

  @override
  State<_SubstackSection> createState() => _SubstackSectionState();
}

class _SubstackSectionState extends State<_SubstackSection> with _Busy {
  final _handle = TextEditingController();

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  Future<void> _connect() => run(() async {
        final n = await widget.library.connectSubstack(_handle.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Found $n publications you follow')));
        }
      });

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline);
    if (lib.substackHandle == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Posts from the publications you follow, each sorted into a story, poem or essay by its content. '
              'Enter your Substack username: the app reads your follows from your public profile, so no password is needed.',
              style: hint,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _handle,
                    decoration: const InputDecoration(hintText: '@username or profile link'),
                    onSubmitted: (_) => _connect(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: busy ? null : _connect, child: busy ? _spinner : const Text('Connect')),
              ],
            ),
          ],
        ),
      );
    }
    final on = lib.substackPubs.where((p) => p.on).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '@${lib.substackHandle} follows ${lib.substackPubs.length} publications that post; $on in use. '
            'Together they count as one source, so following many doesn\'t crowd out the others. '
            'Tap one to open it on Substack.',
            style: hint,
          ),
        ),
        for (final pub in lib.substackPubs)
          ListTile(
            title: Text(pub.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                if (pub.lastPost != null) 'last post ${_ago(pub.lastPost!)}',
                if (pub.paid) 'paid',
                pub.host,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Opens the publication on Substack (its app if installed, or the browser).
            onTap: () => launchUrl(pub.page, mode: LaunchMode.externalApplication),
            contentPadding: const EdgeInsets.only(left: 16, right: 8),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<ReadingType?>(
                  value: pub.type,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('By content')),
                    for (final t in ReadingType.values) DropdownMenuItem(value: t, child: Text(t.shortLabel)),
                  ],
                  onChanged: (t) => lib.setSubstackPub(pub, type: () => t),
                ),
                Switch(value: pub.on, onChanged: (v) => lib.setSubstackPub(pub, on: v)),
              ],
            ),
          ),
        ListTile(
          leading: Icon(lib.substack.signedIn ? Icons.lock_open : Icons.lock_outline),
          title: Text(lib.substack.signedIn ? 'Signed in: paid posts unlocked' : 'Paid posts (optional)'),
          subtitle: Text(lib.substack.signedIn
              ? 'The session is only sent to substack.com'
              : 'Free posts work without this. Sign in only to read posts behind your paid subscriptions.'),
          trailing: lib.substack.signedIn
              ? TextButton(onPressed: lib.signOutSubstack, child: const Text('Sign out'))
              : const Icon(Icons.chevron_right),
          onTap: lib.substack.signedIn
              ? null
              : () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubstackLoginScreen(library: lib))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: busy ? null : () => run(lib.refreshSubstack),
                icon: busy ? _spinner : const Icon(Icons.refresh),
                label: const Text('Refresh list'),
              ),
              const Spacer(),
              TextButton(onPressed: lib.disconnectSubstack, child: const Text('Disconnect')),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotionSection extends StatefulWidget {
  final Library library;
  const _NotionSection({required this.library});

  @override
  State<_NotionSection> createState() => _NotionSectionState();
}

class _NotionSectionState extends State<_NotionSection> with _Busy {
  /// Opens Notion's sign-in in the browser: the phone's own browser first,
  /// then an in-app browser tab, and as a last resort the link to copy.
  Future<void> _signInWithNotion() async {
    final url = await widget.library.startNotionSignIn();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Opening Notion in your browser… Approve, then you come back here.')));
    for (final mode in [LaunchMode.externalApplication, LaunchMode.inAppBrowserView, LaunchMode.platformDefault]) {
      try {
        if (await launchUrl(url, mode: mode)) return;
      } catch (e) {
        debugPrint('Opening Notion sign-in ($mode) failed: $e');
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open this link in a browser'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The browser didn\'t open by itself. Copy the link, paste it into your browser, '
                'approve, and you\'ll come back to the app.'),
            const SizedBox(height: 12),
            SelectableText('$url', style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: '$url')),
            child: const Text('Copy link'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _connected(int? n) async {
    if (n != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connected: $n nightly reads found')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline);
    if (!lib.notion.signedIn) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Read the atlas rows ticked "${NotionAccount.nightlyProperty}" (short articles, Wikipedia entries) '
                'among the essays. The database is found by that checkbox; there\'s no ID to type.', style: hint),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (NotionAccount.oauthAvailable && NotionLoginScreen.supported) ...[
                  // In the app: Android would hand Notion's pages to the Notion app.
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () async => _connected(await Navigator.push<int>(
                            context, MaterialPageRoute(builder: (_) => NotionLoginScreen(library: lib)))),
                    icon: const Icon(Icons.login),
                    label: const Text('Connect with Notion'),
                  ),
                  // In the phone's browser, for Google sign-in; Notion sends the
                  // browser back to the app, see HomeShell._onLink.
                  TextButton(
                    onPressed: busy ? null : () => run(_signInWithNotion),
                    child: const Text('Sign in in the browser instead'),
                  ),
                ],
                // Without a built-in integration, everyone connects their own.
                if (NotionAccount.oauthAvailable)
                  TextButton(
                    onPressed: () async => _connected(
                        await showDialog<int>(context: context, builder: (_) => _NotionSecretDialog(library: lib))),
                    child: const Text('Use an integration secret'),
                  )
                else
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () async => _connected(
                            await showDialog<int>(context: context, builder: (_) => _NotionSecretDialog(library: lib))),
                    icon: const Icon(Icons.key),
                    label: const Text('Connect Notion'),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    final dbs = lib.notion.databases;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.table_chart_outlined),
          title: Text(lib.notion.databaseTitle ?? 'Database'),
          subtitle: Text(lib.atlas.description, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: dbs.length > 1
              ? PopupMenuButton<NotionDatabase>(
                  tooltip: 'Use another database',
                  icon: const Icon(Icons.swap_horiz),
                  itemBuilder: (_) => [for (final d in dbs) PopupMenuItem(value: d, child: Text(d.title))],
                  onSelected: (d) => run(() => lib.useNotionDatabase(d)),
                )
              : null,
        ),
        SwitchListTile(
          value: lib.isEnabled(lib.atlas),
          onChanged: (v) => lib.setEnabled(lib.atlas, v),
          title: const Text('Use among the essays'),
        ),
        SwitchListTile(
          value: lib.notion.syncRead,
          onChanged: lib.setNotionSyncRead,
          title: const Text('Mark as Read in Notion'),
          subtitle: const Text('When you finish one in the app, its Status in the atlas becomes Read'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: busy ? null : () => run(lib.refreshNotion),
                icon: busy ? _spinner : const Icon(Icons.refresh),
                label: const Text('Refresh list'),
              ),
              const Spacer(),
              TextButton(onPressed: lib.disconnectNotion, child: const Text('Disconnect')),
            ],
          ),
        ),
      ],
    );
  }
}

class _NotionSecretDialog extends StatefulWidget {
  final Library library;
  const _NotionSecretDialog({required this.library});

  @override
  State<_NotionSecretDialog> createState() => _NotionSecretDialogState();
}

class _NotionSecretDialogState extends State<_NotionSecretDialog> {
  final _token = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = _token.text.trim();
    if (token.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final n = await widget.library.connectNotion(token);
      if (!mounted) {
        // Cancelled while checking: don't stay connected behind the user's back.
        await widget.library.disconnectNotion();
        return;
      }
      Navigator.pop(context, n);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).textTheme.bodySmall!.copyWith(color: Theme.of(context).colorScheme.outline);
    return AlertDialog(
      title: const Text('Integration secret'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. On notion.so/my-integrations, make a new internal integration and copy its secret.\n'
                '2. In Notion, open your reading database (it needs a "${NotionAccount.nightlyProperty}" '
                'checkbox), then ••• › Connections › add the integration.\n'
                '3. Paste the secret here.\n\n'
                'It stays on this device and is only sent to api.notion.com.', style: hint),
            const SizedBox(height: 8),
            TextField(
              controller: _token,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Integration secret', hintText: 'ntn_…'),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _checking ? null : _save, child: _checking ? _spinner : const Text('Connect')),
      ],
    );
  }
}

/// "Add a source by link", e.g. for a link shared from another app. A shared
/// link's type is unknown, so it starts as "By content".
Future<void> showAddSourceDialog(BuildContext context, Library library, {String? url, ReadingType? type}) =>
    showDialog(context: context, builder: (_) => _AddFeedDialog(library: library, type: type, url: url));

class _AddFeedDialog extends StatefulWidget {
  final Library library;
  final ReadingType? type;
  final String? url;
  const _AddFeedDialog({required this.library, required this.type, this.url});

  @override
  State<_AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<_AddFeedDialog> {
  late final _url = TextEditingController(text: widget.url);
  final _name = TextEditingController();
  late ReadingType? _type = widget.type;
  String? _lang; // null: detect
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var url = _url.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http')) url = 'https://$url';
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final found = await FeedSource.discover(url);
      if (!mounted) return; // Cancelled while looking.
      final name = _name.text.trim().isEmpty ? found.title : _name.text.trim();
      final lang = _lang ?? found.lang;
      await widget.library.addFeed(name: name, url: found.url, type: _type, lang: lang, site: found.site);
      if (mounted) {
        final how = found.site ? 'no feed, so its article links will be read' : 'feed found';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added $name: $how; ${languageOf(lang).name} (tap it to change)')));
      }
      if (mounted) Navigator.pop(context);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = 'Could not use that link: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a source by link'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Link',
                hintText: 'A site, blog, magazine or feed',
                helperText: 'Its feed is found for you; without one, its article links are read.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name (optional)')),
            const SizedBox(height: 8),
            LanguagePicker(value: _lang, noneLabel: 'Detect language', onChanged: (c) => setState(() => _lang = c)),
            const SizedBox(height: 16),
            const Text('Entries count as'),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _TypeChoice(value: _type, onChanged: (t) => setState(() => _type = t)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _checking ? null : _save, child: _checking ? _spinner : const Text('Add')),
      ],
    );
  }
}

/// A dropdown of languages; [noneLabel] names the null choice.
class LanguagePicker extends StatelessWidget {
  final String? value;
  final String noneLabel;
  final ValueChanged<String?> onChanged;
  const LanguagePicker({super.key, required this.value, required this.noneLabel, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String?>(
      value: value,
      isExpanded: true,
      items: [
        DropdownMenuItem(value: null, child: Text(noneLabel)),
        for (final l in languages.values) DropdownMenuItem(value: l.code, child: Text(l.label)),
        // A code the app has no name for (e.g. from a feed's <language> tag).
        if (value != null && !languages.containsKey(value))
          DropdownMenuItem(value: value, child: Text(languageOf(value!).label)),
      ],
      onChanged: onChanged,
    );
  }
}

/// "today", "3 days ago", "5 weeks ago", "2 years ago".
String _ago(DateTime when, [DateTime? now]) {
  final days = (now ?? DateTime.now()).difference(when).inDays;
  if (days < 1) return 'today';
  if (days < 14) return '$days day${days == 1 ? '' : 's'} ago';
  if (days < 60) return '${days ~/ 7} weeks ago';
  if (days < 730) return '${days ~/ 30} months ago';
  return '${days ~/ 365} years ago';
}
