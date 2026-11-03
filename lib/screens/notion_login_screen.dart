import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/library.dart';
import '../services/notion_account.dart';

/// "Connect with Notion" inside the app. Notion's sign-in forwards to
/// app.notion.com, which Android hands to the Notion app when it is installed,
/// and that app can't finish this flow. A WebView keeps every step here, and
/// the redirect back is caught before it loads. Pops with the number of
/// nightly reads found.
class NotionLoginScreen extends StatefulWidget {
  final Library library;
  const NotionLoginScreen({super.key, required this.library});

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<NotionLoginScreen> createState() => _NotionLoginScreenState();
}

class _NotionLoginScreenState extends State<NotionLoginScreen> {
  final _web = WebViewController();
  bool _loading = true;
  bool _finishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _web
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => mounted ? setState(() => _loading = true) : null,
        onPageFinished: (_) => mounted ? setState(() => _loading = false) : null,
        onNavigationRequest: _onNavigation,
      ));
    widget.library.startNotionSignIn().then((url) => _web.loadRequest(url));
  }

  NavigationDecision _onNavigation(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.prevent;
    // The reply: the https page Notion redirects to, or the app link it passes on to.
    if (req.url.startsWith(NotionAccount.redirectUri) || Library.isNotionCallback(uri)) {
      _finish(uri);
      return NavigationDecision.prevent;
    }
    // Keep everything in this view: no hand-off to the Notion app or elsewhere.
    return uri.isScheme('https') || uri.isScheme('http') ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  Future<void> _finish(Uri uri) async {
    if (_finishing) return;
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      final n = await widget.library.finishNotionSignIn(uri);
      if (mounted) Navigator.pop(context, n);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Connect with Notion')),
      body: Column(
        children: [
          if (_loading || _finishing) const LinearProgressIndicator(minHeight: 2),
          Material(
            color: theme.colorScheme.surfaceContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                _error ??
                    (_finishing
                        ? 'Connecting…'
                        : 'Sign in with your email (Google and Apple buttons don\'t work inside apps), then choose '
                            'the atlas\'s Sources database when Notion asks which pages to share.'),
                style: theme.textTheme.bodySmall!.copyWith(color: _error == null ? null : theme.colorScheme.error),
              ),
            ),
          ),
          Expanded(child: WebViewWidget(controller: _web)),
        ],
      ),
    );
  }
}
