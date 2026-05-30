import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Full-screen in-app WebView for hosted 360° tours (e.g. Teleport360).
/// Same experience as Tourism dashboard opening the tour in the browser.
class HostedVrTourScreen extends StatefulWidget {
  const HostedVrTourScreen({
    super.key,
    required this.url,
    required this.title,
  });

  final String url;
  final String title;

  @override
  State<HostedVrTourScreen> createState() => _HostedVrTourScreenState();
}

class _HostedVrTourScreenState extends State<HostedVrTourScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
    _controller.loadRequest(Uri.parse(widget.url));
  }

  WebViewController _buildController() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);

    if (controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      android.setMediaPlaybackRequiresUserGesture(false);
    }

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _error = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (err) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = err.description.isNotEmpty
                    ? err.description
                    : 'Could not load VR tour';
              });
            }
          },
        ),
      );

    return controller;
  }

  Future<void> _openInExternalBrowser() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            onPressed: _openInExternalBrowser,
            icon: const Icon(Icons.open_in_browser),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Loading 360° tour…',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          if (_error != null && !_loading)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: Colors.white54,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        _controller.loadRequest(Uri.parse(widget.url));
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _openInExternalBrowser,
                      icon: const Icon(Icons.open_in_browser, color: Colors.white70),
                      label: const Text(
                        'Open in browser instead',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
