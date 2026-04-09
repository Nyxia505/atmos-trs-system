import 'package:flutter/material.dart';

/// Full-screen single-image VR preview (municipalities without an external tour URL).
/// Uses [BoxFit.contain] so photos are not stretched or squashed.
class SimpleImageVrScreen extends StatelessWidget {
  const SimpleImageVrScreen({
    super.key,
    required this.title,
    required this.imageUrl,
  });

  final String title;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Center(
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _buildImage(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImage() {
    final url = imageUrl.trim();
    if (url.isEmpty) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
      );
    }
    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator(color: Colors.white54));
      },
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
      ),
    );
  }
}
