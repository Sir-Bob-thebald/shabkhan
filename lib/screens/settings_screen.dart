import 'package:flutter/material.dart';

import '../models/languages.dart';
import '../services/library.dart';
import '../services/reminder.dart';
import '../services/translator.dart';
import '../theme.dart';
import 'sources_screen.dart' show LanguagePicker;

class SettingsScreen extends StatelessWidget {
  final Library library;
  const SettingsScreen({super.key, required this.library});

  Future<void> _setReminder(BuildContext context, bool on, TimeOfDay time) async {
    if (on && !await Reminder.requestPermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notifications are blocked for this app in system settings.')),
        );
      }
      return;
    }
    await library.setReminder(on, time);
    on ? await Reminder.scheduleDaily(time) : await Reminder.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) => ListView(
          children: [
            if (Reminder.supported) ...[
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Nightly reminder'),
                subtitle: Text(library.reminderOn
                    ? 'Every night at ${library.reminderTime.format(context)}'
                    : 'Off'),
                value: library.reminderOn,
                onChanged: (v) => _setReminder(context, v, library.reminderTime),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Reminder time'),
                trailing: Text(library.reminderTime.format(context)),
                enabled: library.reminderOn,
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: library.reminderTime);
                  if (t != null && context.mounted) await _setReminder(context, true, t);
                },
              ),
              const Divider(),
            ],
            _LanguagesSection(library: library),
            const Divider(),
            _TranslationSection(library: library),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('Theme'),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final t in AppTheme.values) _ThemeSwatch(library: library, theme: t)],
                ),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.palette_outlined),
              title: const Text('A work of art with each reading'),
              subtitle: const Text('A public-domain painting from The Met or Wikimedia Commons, chosen by what the '
                  'text is about, where it comes from and when. Only shown when online.'),
              value: library.artOn,
              onChanged: library.setArtOn,
            ),
            ListTile(
              leading: const Icon(Icons.format_size),
              title: const Text('Reading text size'),
              subtitle: Slider(
                value: library.textScale,
                min: 0.8,
                max: 1.8,
                divisions: 10,
                label: '${(library.textScale * 100).round()}%',
                onChanged: library.setTextScale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// One slider per language the user's sources come in. Values are relative:
/// Russian 50, French 25, German 25 gives half the nights in Russian.
class _LanguagesSection extends StatelessWidget {
  final Library library;
  const _LanguagesSection({required this.library});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline);
    final langs = library.languages;
    final uneven = langs.any((c) => library.langWeight(c) != Library.defaultLangWeight);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header('Languages'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            langs.length < 2
                ? 'Add sources in another language (a feed, a Substack, the catalog) to set how often each comes up.'
                : 'How often each language comes up. The numbers are relative: 50, 25 and 25 means half your '
                    'nights in the first. 0 means never. The list comes from your sources.',
            style: hint,
          ),
        ),
        for (final code in langs)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                SizedBox(width: 120, child: Text(languageOf(code).label, maxLines: 2)),
                Expanded(
                  child: Slider(
                    value: library.langWeight(code).toDouble(),
                    max: 100,
                    divisions: 20,
                    label: '${library.langWeight(code)}',
                    onChanged: (v) => library.setLangWeight(code, v.round()),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text('${(library.langShare(code) * 100).round()}%',
                      textAlign: TextAlign.end, style: theme.textTheme.labelLarge),
                ),
              ],
            ),
          ),
        if (uneven)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextButton.icon(
              onPressed: library.evenOutLanguages,
              icon: const Icon(Icons.balance),
              label: const Text('Even out'),
            ),
          ),
      ],
    );
  }
}

class _TranslationSection extends StatefulWidget {
  final Library library;
  const _TranslationSection({required this.library});

  @override
  State<_TranslationSection> createState() => _TranslationSectionState();
}

class _TranslationSectionState extends State<_TranslationSection> {
  late final _url = TextEditingController(text: widget.library.libreUrl);
  late final _key = TextEditingController(text: widget.library.libreKey);

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header('Translation'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'The Translate button in the reader uses machine translation, not an AI model. It works well for '
            'prose; poems lose their form. To translate a source every time, set that from its sheet in Sources.',
            style: hint,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              const Text('Translate into'),
              const SizedBox(width: 16),
              Expanded(
                child: LanguagePicker(
                  value: lib.translateTo,
                  noneLabel: '—',
                  onChanged: (c) => c == null ? null : lib.setTranslation(to: c),
                ),
              ),
            ],
          ),
        ),
        RadioGroup<TranslatorKind>(
          groupValue: lib.translatorKind,
          onChanged: (v) => lib.setTranslation(kind: v),
          child: Column(
            children: [
              for (final k in TranslatorKind.values)
                RadioListTile<TranslatorKind>(value: k, title: Text(k.label), subtitle: Text(k.blurb)),
            ],
          ),
        ),
        if (lib.translatorKind == TranslatorKind.libre)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Server', hintText: 'https://libretranslate.example'),
                  onChanged: (v) => lib.setTranslation(libreUrl: v),
                ),
                TextField(
                  controller: _key,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API key (if the server needs one)'),
                  onChanged: (v) => lib.setTranslation(libreKey: v),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A small preview of a theme: its background, text and accent.
class _ThemeSwatch extends StatelessWidget {
  final Library library;
  final AppTheme theme;
  const _ThemeSwatch({required this.library, required this.theme});

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final selected = library.theme == theme;
    return Semantics(
      selected: selected,
      button: true,
      label: '${theme.label} theme',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => library.setTheme(theme),
        child: Container(
          width: 72,
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : p.steps[4],
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 18, height: 18, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle)),
              const SizedBox(height: 8),
              Container(height: 3, width: 44, color: p.text),
              const SizedBox(height: 4),
              Container(height: 3, width: 30, color: p.muted),
              const SizedBox(height: 8),
              Text(theme.label, style: TextStyle(color: p.text, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
