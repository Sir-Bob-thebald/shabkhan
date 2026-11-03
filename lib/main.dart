import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/settings_screen.dart';
import 'screens/shelf_screens.dart';
import 'screens/sources_screen.dart';
import 'screens/tonight_screen.dart';
import 'services/library.dart';
import 'services/reminder.dart';

/// The app's name in its two languages.
const appNameFa = 'شبخوان';
const appNameEn = 'Nightly Reader';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final library = await Library.load();
  await Reminder.init();
  runApp(NightlyReaderApp(library: library));
}

class NightlyReaderApp extends StatelessWidget {
  final Library library;
  const NightlyReaderApp({super.key, required this.library});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) => MaterialApp(
        title: '$appNameEn · $appNameFa',
        debugShowCheckedModeBanner: false,
        theme: library.theme.data,
        home: HomeShell(library: library),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  final Library library;
  const HomeShell({super.key, required this.library});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  /// Links shared from other apps (Android "Share → Nightly Reader").
  static const _share = MethodChannel('nightly_reader/share');
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.library.ensureTonight();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _share.setMethodCallHandler((call) async {
        if (call.method == 'shared') _onShared(call.arguments as String?);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          _onShared(await _share.invokeMethod<String>('takeShared'));
        } on MissingPluginException {
          // Not running inside the Android app (tests).
        } on PlatformException catch (e) {
          debugPrint('Could not read a shared link: $e');
        }
      });
    }
  }

  /// Opens "Add a source by link" for the first link in a shared text.
  void _onShared(String? text) {
    final url = RegExp(r'https?://\S+').firstMatch(text ?? '')?.group(0);
    if (url == null || !mounted) return;
    setState(() => _tab = 3);
    showAddSourceDialog(context, widget.library, url: url);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back the next evening should show a fresh set.
    if (state == AppLifecycleState.resumed) widget.library.ensureTonight();
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    final theme = Theme.of(context);
    const titles = ['Tonight', 'Past nights', 'Saved', 'Sources'];
    return Scaffold(
      appBar: AppBar(
        title: _tab == 0
            ? Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/logo.png', width: 34, height: 34),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appNameFa, style: theme.textTheme.titleLarge!.copyWith(height: 1.1)),
                      Text(appNameEn,
                          style: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.primary, letterSpacing: 1.2)),
                    ],
                  ),
                ],
              )
            : Text(titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(library: lib))),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          TonightScreen(library: lib),
          HistoryScreen(library: lib),
          SavedScreen(library: lib),
          SourcesScreen(library: lib),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.nights_stay_outlined), selectedIcon: Icon(Icons.nights_stay), label: 'Tonight'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Past'),
          NavigationDestination(icon: Icon(Icons.bookmark_outline), selectedIcon: Icon(Icons.bookmark), label: 'Saved'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Sources'),
        ],
      ),
    );
  }
}
