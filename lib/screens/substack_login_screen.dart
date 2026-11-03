import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/library.dart';
import '../services/substack_account.dart';

/// Optional sign-in, only needed for paid posts: Substack's own page inside
/// the app, then the session is kept. Returns `true` via Navigator.pop when signed in.
class SubstackLoginScreen extends StatelessWidget {
  final Library library;
  const SubstackLoginScreen({super.key, required this.library});

  static bool get webViewSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Substack: paid posts')),
      body: webViewSupported ? _WebLogin(library: library) : _ManualLogin(library: library),
    );
  }
}

class _WebLogin extends StatefulWidget {
  final Library library;
  const _WebLogin({required this.library});

  @override
  State<_WebLogin> createState() => _WebLoginState();
}

class _WebLoginState extends State<_WebLogin> {
  late final WebViewController _web;
  final _link = TextEditingController();
  final _cookies = WebViewCookieManager();
  String? _lastTried;
  bool _checking = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // As a desktop browser, Substack shows its web sign-in instead of pushing its app.
      ..setUserAgent(_desktopAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _onNavigation,
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) {
          setState(() => _loading = false);
          _checkSession();
        },
      ))
      ..loadRequest(Uri.parse('https://substack.com/sign-in'));
  }

  static const _desktopAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

  /// Keeps sign-in inside this view: links to the Substack app, the Play
  /// Store or other apps (intent://, substack://, market://) are dropped.
  NavigationDecision _onNavigation(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    final web = uri != null && (uri.isScheme('https') || uri.isScheme('http'));
    final store = uri != null && (uri.host == 'play.google.com' || uri.host == 'apps.apple.com');
    return web && !store ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  /// After each page load, see whether Substack has issued a signed-in session.
  Future<void> _checkSession() async {
    if (_checking) return;
    final cookies = await _cookies.getCookies(domain: Uri.parse('https://substack.com'));
    final sid = cookies.where((c) => c.name == SubstackAccount.cookieName).firstOrNull?.value;
    // Substack may set this cookie before login too; only a session that can
    // list subscriptions counts, so failed tries are silent and we keep waiting.
    if (sid == null || sid.isEmpty || sid == _lastTried) return;
    _checking = true;
    _lastTried = sid;
    try {
      await widget.library.signInSubstack(sid);
      if (mounted) Navigator.pop(context, true);
    } on Exception {
      // Not signed in yet.
    } finally {
      _checking = false;
    }
  }

  void _openLink() {
    final uri = Uri.tryParse(_link.text.trim());
    if (uri == null || !uri.isScheme('https')) return;
    FocusScope.of(context).unfocus();
    _web.loadRequest(uri);
    _link.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: WebViewWidget(controller: _web)),
        Material(
          color: theme.colorScheme.surfaceContainer,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Only needed for paid posts. Sign in with your email (Google and Apple buttons don\'t work '
                    'inside apps). If Substack emails you a code, type it above. If it emails a link, long-press '
                    'it, copy it and paste it here, so it opens in this view instead of the Substack app:',
                    style: theme.textTheme.bodySmall,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _link,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(hintText: 'https://substack.com/…', isDense: true),
                          onSubmitted: (_) => _openLink(),
                        ),
                      ),
                      IconButton(tooltip: 'Open link', icon: const Icon(Icons.login), onPressed: _openLink),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Desktop fallback: paste the session cookie from a browser where you're signed in.
class _ManualLogin extends StatefulWidget {
  final Library library;
  const _ManualLogin({required this.library});

  @override
  State<_ManualLogin> createState() => _ManualLoginState();
}

class _ManualLoginState extends State<_ManualLogin> {
  final _sid = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _sid.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_sid.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.library.signInSubstack(Uri.decodeComponent(_sid.text.trim()));
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = 'That session didn\'t work: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'In-app sign-in works on phones. On this device, copy your session from a browser '
          'where you\'re signed in to Substack:\n\n'
          '1. Open substack.com and press F12.\n'
          '2. Application (Chrome) or Storage (Firefox) → Cookies → https://substack.com\n'
          '3. Copy the value of "substack.sid" and paste it below.\n\n'
          'It\'s stored in this device\'s secure storage and only sent to substack.com.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _sid,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'substack.sid', border: OutlineInputBorder()),
          onSubmitted: (_) => _save(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Sign in'),
        ),
      ],
    );
  }
}
