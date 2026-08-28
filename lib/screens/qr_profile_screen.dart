import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/qr_registry_service.dart';

class QrProfileScreen extends StatefulWidget {
  const QrProfileScreen({
    super.key,
    required this.touristId,
    required this.fullName,
    required this.location,
    this.isAfterRegistration = false,
  });

  /// Firebase Auth UID of the logged-in tourist (encoded in QR as tourist_id).
  final String touristId;
  final String fullName;
  final String location;
  final bool isAfterRegistration;

  /// JSON payload for the tourist QR: {"type":"tourist","tourist_id":"<uid>"}.
  static String buildTouristQrData(String firebaseUid) {
    return jsonEncode(<String, String>{
      'type': 'tourist',
      'tourist_id': firebaseUid,
    });
  }

  static const Color _backgroundWhite = Color(0xFFF8FAFC);
  static const Color _cardWhite = Colors.white;
  static const Color _textDark = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF6B7280);
  @override
  State<QrProfileScreen> createState() => _QrProfileScreenState();
}

class _QrProfileScreenState extends State<QrProfileScreen> {
  final GlobalKey _qrCardKey = GlobalKey();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _storeQrInFirestore();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryUploadQrCardToStorageWithRetry();
    });
  }

  Future<void> _storeQrInFirestore() async {
    final payload = QrProfileScreen.buildTouristQrData(widget.touristId);
    await QrRegistryService.upsertTouristQr(
      touristId: widget.touristId,
      payload: payload,
      fullName: widget.fullName,
      location: widget.location,
    );
  }

  Future<Uint8List?> _captureQrCardPngBytes() async {
    final boundary =
        _qrCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final ui.Image image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final png = byteData?.buffer.asUint8List();
    if (png == null || png.isEmpty) return null;
    return png;
  }

  /// Layout may need a frame or two before [RepaintBoundary] is ready.
  Future<void> _tryUploadQrCardToStorageWithRetry() async {
    for (var i = 0; i < 4; i++) {
      if (!mounted) return;
      final bytes = await _captureQrCardPngBytes();
      if (bytes != null && bytes.isNotEmpty) {
        await QrRegistryService.uploadQrCardPng(
          touristId: widget.touristId,
          pngBytes: bytes,
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  Future<void> _saveOrShareQrCard() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final boundary =
          _qrCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('QR card is not ready yet.');
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null || pngBytes.isEmpty) {
        throw Exception('Unable to capture QR image.');
      }

      await QrRegistryService.uploadQrCardPng(
        touristId: widget.touristId,
        pngBytes: pngBytes,
      );

      final fileName =
          'asenso_turismo_qr_${DateTime.now().millisecondsSinceEpoch}';
      if (kIsWeb) {
        final xfile = XFile.fromData(
          pngBytes,
          mimeType: 'image/png',
          name: '$fileName.png',
        );
        await SharePlus.instance.share(
          ShareParams(
            files: [xfile],
            text: 'My Asenso Turismo QR Code',
            title: 'Asenso Turismo QR',
          ),
        );
      } else {
        final result = await ImageGallerySaverPlus.saveImage(
          pngBytes,
          quality: 100,
          name: fileName,
        );
        final ok =
            result is Map &&
            (result['isSuccess'] == true || result['success'] == true);
        if (!ok) {
          throw Exception('Gallery save failed');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'QR image is ready to download/share.'
                : 'QR code saved to your gallery.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not export QR image. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QrProfileScreen._backgroundWhite,
      appBar: widget.isAfterRegistration
          ? null
          : AppBar(
              backgroundColor: QrProfileScreen._backgroundWhite,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: QrProfileScreen._textDark,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                'My QR Code',
                style: TextStyle(
                  color: QrProfileScreen._textDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
              centerTitle: true,
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (widget.isAfterRegistration) ...[
                  const SizedBox(height: 20),
                  Icon(
                    Icons.check_circle,
                    color: AppTheme.primary,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Registration Successful!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: QrProfileScreen._textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your Tourist ID has been generated',
                    style: TextStyle(
                      fontSize: 14,
                      color: QrProfileScreen._textMuted.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],

                // Main QR Card
                RepaintBoundary(
                  key: _qrCardKey,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: QrProfileScreen._cardWhite,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Tourist ID',
                            style: TextStyle(
                              color: AppTheme.primaryDark,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),

                        // Header
                        const Padding(
                          padding: EdgeInsets.fromLTRB(24, 18, 24, 12),
                          child: Text(
                            'My Asenso Turismo QR Code',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: QrProfileScreen._textDark,
                            ),
                          ),
                        ),

                        // Description
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'This is your personal Tourist ID. Save a copy of your QR Code for quick check-ins at tourist destinations in Misamis Occidental.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: QrProfileScreen._textMuted.withOpacity(
                                0.85,
                              ),
                              height: 1.45,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Banner Image with QR Code overlay
                        Stack(
                          alignment: Alignment.bottomCenter,
                          clipBehavior: Clip.none,
                          children: [
                            // Banner Image
                            Container(
                              width: double.infinity,
                              height: 120,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.primaryLight,
                                    AppTheme.primary,
                                    AppTheme.primaryDark,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CustomPaint(
                                  painter: _AbstractArtPainter(),
                                  size: const Size(double.infinity, 120),
                                ),
                              ),
                            ),

                            // QR Code
                            Positioned(
                              bottom: -60,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: QrImageView(
                                  data: QrProfileScreen.buildTouristQrData(
                                    widget.touristId,
                                  ),
                                  version: QrVersions.auto,
                                  size: 140,
                                  backgroundColor: Colors.white,
                                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 80),

                        // User Info
                        Text(
                          widget.fullName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: QrProfileScreen._textDark,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            widget.location.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: QrProfileScreen._textMuted.withOpacity(
                                0.8,
                              ),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),

                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Save Image Button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveOrShareQrCard,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    label: Text(
                      _isSaving ? 'Saving QR...' : 'Save QR Code',
                    ),
                  ),
                ),

                if (widget.isAfterRegistration) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/dashboard');
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryDark,
                        foregroundColor: AppTheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Continue to Dashboard',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AbstractArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Background gradient shapes (theme accent)
    paint.color = AppTheme.primary.withValues(alpha: 0.75);
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.3), 60, paint);

    paint.color = AppTheme.primaryLight.withValues(alpha: 0.65);
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.6), 80, paint);

    paint.color = AppTheme.primaryDark.withValues(alpha: 0.55);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.2), 40, paint);

    paint.color = AppTheme.primaryDark.withValues(alpha: 0.5);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.3), 50, paint);

    // Abstract lines
    paint.color = Colors.white.withOpacity(0.3);
    paint.strokeWidth = 2;
    paint.style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height * 0.5);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.2,
      size.width * 0.5,
      size.height * 0.5,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.8,
      size.width,
      size.height * 0.4,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
