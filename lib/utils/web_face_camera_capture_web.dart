// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:flutter/material.dart';

/// Opens a live webcam preview on web and returns a JPEG snapshot.
Future<Uint8List?> showWebFaceCameraCapture(BuildContext context) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _WebFaceCameraDialog(),
  );
}

class _WebFaceCameraDialog extends StatefulWidget {
  const _WebFaceCameraDialog();

  @override
  State<_WebFaceCameraDialog> createState() => _WebFaceCameraDialogState();
}

class _WebFaceCameraDialogState extends State<_WebFaceCameraDialog> {
  static const _previewHeight = 320.0;

  html.VideoElement? _video;
  html.MediaStream? _stream;
  String? _viewType;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final devices = html.window.navigator.mediaDevices;
      if (devices == null) {
        setState(() {
          _error = 'Camera is not supported in this browser.';
        });
        return;
      }

      final stream = await devices.getUserMedia({
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
        'audio': false,
      });

      final video = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..setAttribute('playsinline', 'true')
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        // Use non-mirrored preview so left/right match movement.
        ..style.transform = 'scaleX(-1)'
        ..srcObject = stream;

      await video.onLoadedMetadata.first.timeout(const Duration(seconds: 8));

      final viewType = 'face-camera-${DateTime.now().microsecondsSinceEpoch}';
      ui_web.platformViewRegistry.registerViewFactory(
        viewType,
        (int _) => video,
      );

      if (!mounted) {
        _stopStream(stream);
        return;
      }

      setState(() {
        _video = video;
        _stream = stream;
        _viewType = viewType;
        _ready = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not access the camera. Allow camera permission and try again.';
      });
    }
  }

  void _stopStream([html.MediaStream? stream]) {
    final active = stream ?? _stream;
    if (active == null) return;
    for (final track in active.getTracks()) {
      track.stop();
    }
  }

  Future<void> _capture() async {
    final video = _video;
    if (video == null) return;

    final width = video.videoWidth;
    final height = video.videoHeight;
    if (width == 0 || height == 0) return;

    const maxSide = 800;
    final scale = width > height
        ? maxSide / width
        : maxSide / height;
    final targetW = (width * scale).round().clamp(1, maxSide);
    final targetH = (height * scale).round().clamp(1, maxSide);

    final canvas = html.CanvasElement(width: targetW, height: targetH);
    canvas.context2D.drawImageScaled(video, 0, 0, targetW, targetH);
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.85);
    final comma = dataUrl.indexOf(',');
    if (comma < 0 || !mounted) return;

    final bytes = base64Decode(dataUrl.substring(comma + 1));
    _stopStream();
    Navigator.of(context).pop(Uint8List.fromList(bytes));
  }

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Take a photo'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: _previewHeight,
                color: const Color(0xFF111827),
                child: _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      )
                    : _ready && _viewType != null
                        ? HtmlElementView(viewType: _viewType!)
                        : const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Position your face in the frame, then tap Capture.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _ready && _error == null ? _capture : null,
          icon: const Icon(Icons.camera_alt, size: 18),
          label: const Text('Capture'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.brandOrange,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
