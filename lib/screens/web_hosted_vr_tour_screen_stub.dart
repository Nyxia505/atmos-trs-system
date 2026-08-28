import 'package:flutter/material.dart';

/// Stub — real implementation is web-only ([web_hosted_vr_tour_screen_web.dart]).
class WebHostedVrTourScreen extends StatelessWidget {
  const WebHostedVrTourScreen({
    super.key,
    required this.url,
    required this.title,
  });

  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(
        child: Text('VR tour is only available in a web browser.'),
      ),
    );
  }
}
