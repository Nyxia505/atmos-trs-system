// ignore_for_file: unused_import
//
// VR WebView screen and openVrTour helper.
// - Android/iOS: open in-app via WebView (webview_flutter).
// - Web: open via url_launcher in new tab (no WebView on web).
//

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';

// Only import WebView on non-web platforms to avoid platform registration errors on web.
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

// -----------------------------------------------------------------------------
// Helper: open VR tour (Android/iOS = in-app WebView; Web = url_launcher new tab)
// -----------------------------------------------------------------------------

/// Opens the VR tour: on Android/iOS opens in-app via [VRWebViewScreen];
/// on Web opens [url] in a new browser tab using url_launcher.
///
/// [useLocalTour] – If true, loads the bundled Marzipano VR tour from
///   [kLocalVrTourAssetPath] (Oroquieta City Plaza multi-scene tour).
///   Ignored on web (opens [url] in new tab).
/// [url] – VR tour URL when not using local tour (defaults to [kVrTourUrl] if null).
/// [title] – App bar / dialog title when shown in WebView.
///
/// Loading: Web shows SnackBar "Opening VR tour…"; mobile shows WebView loading overlay.
/// Errors: Invalid URL, launch failure, or load failure show SnackBar (Web) or error UI with Retry (mobile).
Future<void> openVrTour(
  BuildContext context, {
  bool useLocalTour = false,
  String? url,
  String title = 'VR Tour',
}) async {
  if (kIsWeb) {
    final targetUrl = url ?? kVrTourUrl;
    final uri = Uri.tryParse(targetUrl);
    if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
      if (context.mounted) _showError(context, 'Invalid VR tour URL');
      return;
    }
    await _openVrTourOnWeb(context, uri);
    return;
  }

  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    if (!context.mounted) return;
    if (useLocalTour) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VRWebViewScreen(
            title: title,
            useLocalTour: true,
          ),
        ),
      );
      return;
    }
    final targetUrl = url ?? kVrTourUrl;
    final uri = Uri.tryParse(targetUrl);
    if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
      if (context.mounted) _showError(context, 'Invalid VR tour URL');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VRWebViewScreen(title: title, initialUrl: targetUrl),
      ),
    );
    return;
  }

  // Desktop (Windows, macOS, Linux): open in browser (local tour not supported; use url)
  final targetUrl = url ?? kVrTourUrl;
  final uri = Uri.tryParse(targetUrl);
  if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
    await _openInBrowser(context, uri);
  } else if (context.mounted) {
    _showError(context, 'Invalid VR tour URL');
  }
}

/// Convenience: open VR tour with URL as first argument after context.
/// Example: openVrTour(context, 'https://example.com/vr');
Future<void> openVrTourWithUrl(BuildContext context, String url) =>
    openVrTour(context, url: url);

Future<void> _openVrTourOnWeb(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Opening VR tour…'),
        ],
      ),
      backgroundColor: AppTheme.cardBackground,
      duration: const Duration(seconds: 2),
    ),
  );

  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!launched && context.mounted) {
      _showError(context, 'Could not open VR tour');
    }
  } catch (e) {
    if (context.mounted) _showError(context, 'Could not open link: $e');
  }
}

Future<void> _openInBrowser(BuildContext context, Uri uri) async {
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      _showError(context, 'Could not open VR tour');
    }
  } catch (e) {
    if (context.mounted) _showError(context, 'Could not open link: $e');
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

// -----------------------------------------------------------------------------
// VR WebView screen (Android/iOS only; do not push on Web)
// -----------------------------------------------------------------------------

class VRWebViewScreen extends StatefulWidget {
  const VRWebViewScreen({
    super.key,
    this.title = 'VR Tour',
    this.initialUrl,
    this.useLocalTour = false,
  });

  final String title;
  final String? initialUrl;
  final bool useLocalTour;

  @override
  State<VRWebViewScreen> createState() => _VRWebViewScreenState();
}

class _VRWebViewScreenState extends State<VRWebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  bool _useExternalBrowser = false;

  static bool get _isWebViewSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    if (_isWebViewSupported) {
      _initController();
    } else {
      _useExternalBrowser = true;
      _openInBrowser();
    }
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _isLoading = true;
            _hasError = false;
          }),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (error) => setState(() {
            _isLoading = false;
            _hasError = true;
            _errorMessage = error.description.isNotEmpty
                ? error.description
                : 'Failed to load VR tour';
          }),
        ),
      );

    if (widget.useLocalTour) {
      _controller!.loadFlutterAsset(kLocalVrTourAssetPath);
      return;
    }

    final url = widget.initialUrl ?? kVrTourUrl;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Invalid URL';
        _isLoading = false;
      });
      return;
    }
    _controller!.loadRequest(uri);
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.initialUrl ?? kVrTourUrl);
    if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _isLoading = true;
    });
    _initController();
  }

  @override
  Widget build(BuildContext context) {
    if (_useExternalBrowser) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 16),
              Text(
                'Opening in browser…',
                style: TextStyle(color: AppTheme.unselectedMuted),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return _buildErrorState();
    }
    if (_controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (_isLoading) _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: AppTheme.scaffoldBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(
              'Loading VR Tour…',
              style: TextStyle(color: AppTheme.unselectedMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 15),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close', style: TextStyle(color: AppTheme.unselectedMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
