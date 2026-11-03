import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/library.dart';
import '../services/notion_account.dart';

/// "Connect with Notion": Notion's own sign-in and page picker, inside the app.
/// The redirect back is caught before it loads, and its code is swapped for a
/// token. Pops with the number of nightly reads found.
class NotionLoginScreen extends StatefulWidget {
  final Library library;
  const NotionLoginScreen({super.key, required this.library});

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<NotionLoginScreen> createState() => _NotionLoginScreenState();
}

class _NotionLoginScreenState extends State<NotionLoginScreen> {
  late final WebViewController _web;
  final _state = List.generate(16, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
  bool _loading = true;
  bool _finishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onNavigationRequest: _onNavigation,
      ))
      ..loadRequest(NotionAccount.authorizeUrl(_state));
  }

  NavigationDecision _onNavigation(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.prevent;
    if (req.url.startsWith(NotionAccount.redirectUri)) {
      _finish(uri);
      return NavigationDecision.prevent;
    }
    // Keep everything in this view: no hand-off to the Notion app or a browser.
    return uri.isScheme('https') || uri.isScheme('http') ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  Future<void> _finish(Uri uri) async {
    final p = uri.queryParameters;
    if (p['state'] != _state) return setState(() => _error = 'The sign-in reply didn\'t match; try again');
    final code = p['code'];
    if (code == null) {
      return setState(() => _error = p['error'] == 'access_denied' ? 'Access was declined' : 'Notion: ${p['error']}');
    }
    setState(() => _finishing = true);
    try {
      final n = await widget.library.connectNotionWithCode(code);
      if (mounted) Navigator.pop(context, n);
    } on Exception catch (e) {
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
                    'Sign in with your email (Google and Apple buttons don\'t work inside apps), then choose '
                        'the atlas\'s Sources database when Notion asks which pages to share.',
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
