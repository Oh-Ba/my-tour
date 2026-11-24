import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Builds the widget that shows a web page.
typedef SiteViewBuilder = Widget Function(Uri url);

/// How web pages are shown. Tests replace it, as a web view needs a phone.
final siteViewBuilderProvider = Provider<SiteViewBuilder>((ref) {
  return (url) => SiteWebView(url: url);
});

/// A web page inside the app, with a thin progress bar while it loads.
class SiteWebView extends StatefulWidget {
  const SiteWebView({super.key, required this.url});

  final Uri url;

  @override
  State<SiteWebView> createState() => _SiteWebViewState();
}

class _SiteWebViewState extends State<SiteWebView> {
  late final WebViewController _controller;

  /// 0-100 while loading, 100 when done.
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onProgress: _onProgress))
      ..loadRequest(widget.url);
  }

  void _onProgress(int progress) {
    if (mounted) setState(() => _progress = progress);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(key: const Key('placeWebView'), controller: _controller),
        if (_progress < 100) LinearProgressIndicator(value: _progress / 100),
      ],
    );
  }
}
