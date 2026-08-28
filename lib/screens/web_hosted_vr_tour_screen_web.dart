// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Full-screen iframe for hosted 360° tours on Flutter web (no webview_flutter).
class WebHostedVrTourScreen extends StatefulWidget {
  const WebHostedVrTourScreen({
    super.key,
    required this.url,
    required this.title,
  });

  final String url;
  final String title;

  @override
  State<WebHostedVrTourScreen> createState() => _WebHostedVrTourScreenState();
}

class _WebHostedVrTourScreenState extends State<WebHostedVrTourScreen> {
  String? _viewType;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _registerIframe();
  }

  void _registerIframe() {
    final viewType =
        'vr-tour-${widget.url.hashCode}-${DateTime.now().microsecondsSinceEpoch}';

    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int _) {
        final iframe = html.IFrameElement()
          ..src = widget.url
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true
          ..setAttribute(
            'allow',
            'accelerometer; autoplay; clipboard-write; encrypted-media; '
            'gyroscope; picture-in-picture; xr-spatial-tracking',
          );

        iframe.onLoad.listen((_) {
          if (mounted) setState(() => _loading = false);
        });

        return iframe;
      },
    );

    setState(() => _viewType = viewType);

    // Fallback if onLoad never fires (e.g. slow network).
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted && _loading) setState(() => _loading = false);
    });
  }

  Future<void> _openInExternalBrowser() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    await launchUrl(uri, webOnlyWindowName: '_blank');
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
            tooltip: 'Open in new tab',
            onPressed: _openInExternalBrowser,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_viewType != null)
            HtmlElementView(viewType: _viewType!)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_loading)
            const ColoredBox(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white70),
                    SizedBox(height: 16),
                    Text(
                      'Loading 360° tour…',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
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
