import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrProfileScreen extends StatelessWidget {
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
  static const Color _accentTeal = Color(0xFF14B8A6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundWhite,
      appBar: isAfterRegistration
          ? null
          : AppBar(
              backgroundColor: _backgroundWhite,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: _textDark),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                'My QR Code',
                style: TextStyle(color: _textDark, fontWeight: FontWeight.w600),
              ),
              centerTitle: true,
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (isAfterRegistration) ...[
                  const SizedBox(height: 20),
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFFF97316),
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Registration Successful!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your Tourist ID has been generated',
                    style: TextStyle(
                      fontSize: 14,
                      color: _textMuted.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],

                // Main QR Card
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _cardWhite,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Header
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: Text(
                          'My Asenso Turismo QR Code',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _textDark,
                          ),
                        ),
                      ),

                      // Description
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'This is your personal Tourist ID. To ensure you have access to it at all times, please save a copy of your QR Code by either printing it out or taking a screenshot on your mobile device. Bring this QR Code with you whenever you visit a tourist destination in the Province of Misamis Occidental.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: _textMuted.withOpacity(0.8),
                            height: 1.5,
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
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF6366F1),
                                  Color(0xFFEC4899),
                                  Color(0xFFF59E0B),
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
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: QrImageView(
                                data: buildTouristQrData(touristId),
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
                        fullName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        location.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          color: _textMuted.withOpacity(0.8),
                          letterSpacing: 0.3,
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Save Image Button
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('QR Code saved to gallery'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _accentTeal,
                              side: const BorderSide(color: _accentTeal),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Save Image',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (isAfterRegistration) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/dashboard');
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
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

    // Background gradient shapes
    paint.color = const Color(0xFF6366F1).withOpacity(0.8);
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.3), 60, paint);

    paint.color = const Color(0xFFEC4899).withOpacity(0.7);
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.6), 80, paint);

    paint.color = const Color(0xFFF59E0B).withOpacity(0.6);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.2), 40, paint);

    paint.color = const Color(0xFF14B8A6).withOpacity(0.5);
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
