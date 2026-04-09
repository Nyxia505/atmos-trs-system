import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/data/misamis_occidental_places.dart';
import 'package:atmos_trs_system/features/misamis_occidental/misamis_occidental_screen.dart';

/// Hero section: gradient + topographic map, featured label, pins, LAUNCH VR TOUR and See All.
/// [homeStyle] true = "Azure Coast" + orange LAUNCH VR TOUR (home tab); false = Misamis Occidental + white button.
class HeroMapSection extends StatelessWidget {
  const HeroMapSection({
    super.key,
    this.mapImageUrl,
    this.onLaunchVrTour,
    this.onSeeAll,
    this.homeStyle = false,
  });

  /// Optional network image for map; otherwise uses gradient + custom paint.
  final String? mapImageUrl;
  final VoidCallback? onLaunchVrTour;
  final VoidCallback? onSeeAll;
  /// When true, shows "Azure Coast" label and orange LAUNCH VR TOUR pill (home tab style).
  final bool homeStyle;

  static const String _provinceName = 'Misamis Occidental';
  static int get _placeCount => misamisOccidentalPlaces.length;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = _horizontalPadding(context);
    final height = _sectionHeight(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Background: image or gradient + topographic lines
            SizedBox(
              height: height,
              width: double.infinity,
              child: mapImageUrl != null && mapImageUrl!.isNotEmpty
                  ? Image.network(
                      mapImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildGradientMap(height),
                    )
                  : _buildGradientMap(height),
            ),
            // Featured label (white card + star): Azure Coast (home) or Misamis Occidental
            Positioned(
              left: 24,
              top: 24,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (homeStyle)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Azure Coast',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.star_outline, color: AppTheme.primary, size: 18),
                          ],
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _provinceName,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '$_placeCount Municipalities & Cities',
                                  style: TextStyle(
                                    color: AppTheme.unselectedMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.star_outline, color: AppTheme.primary, size: 18),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Location pins
            Positioned(left: 80, top: 56, child: _buildPin(AppTheme.primary, 28)),
            Positioned(right: 100, bottom: 70, child: _buildPin(AppTheme.primary.withOpacity(0.8), 24)),
            Positioned(left: 40, bottom: 90, child: _buildPin(AppTheme.primary.withOpacity(0.8), 22)),
            // LAUNCH VR TOUR pill: orange (home) or white (province)
            Positioned(
              left: 20,
              bottom: 16,
              child: Material(
                color: homeStyle ? AppTheme.primary : Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onLaunchVrTour ?? () => _navigateToVrTour(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      'LAUNCH VR TOUR',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: homeStyle ? Colors.white : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // See All (eye) button
            Positioned(
              right: 20,
              bottom: 16,
              child: Material(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  onTap: onSeeAll ?? () => _navigateToSeeAll(context),
                  borderRadius: BorderRadius.circular(24),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'See All',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientMap(double height) {
    return Stack(
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.cardBackground,
                Color.lerp(AppTheme.scaffoldBackground, AppTheme.cardBackground, 0.5)!,
                AppTheme.scaffoldBackground,
              ],
            ),
          ),
        ),
        CustomPaint(
          size: Size(double.infinity, height),
          painter: _TopographicMapPainter(),
        ),
      ],
    );
  }

  Widget _buildPin(Color color, double size) {
    return Icon(Icons.location_on, color: color.withOpacity(0.9), size: size);
  }

  void _navigateToVrTour(BuildContext context) {
    openVrTour(context, title: 'VR Tour');
  }

  void _navigateToSeeAll(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MisamisOccidentalScreen()),
    );
  }

  static double _horizontalPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return 48;
    if (w >= 600) return 32;
    return 20;
  }

  static double _sectionHeight(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return 280;
    if (w >= 600) return 250;
    return 220;
  }
}

class _TopographicMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < 8; i++) {
      final path = Path();
      final y = 40.0 + i * 22.0;
      path.moveTo(0, y);
      path.quadraticBezierTo(size.width * 0.3, y - 15, size.width * 0.5, y);
      path.quadraticBezierTo(size.width * 0.7, y + 18, size.width, y - 5);
      canvas.drawPath(path, paint);
    }
    final fillPaint = Paint()
      ..color = AppTheme.primary.withOpacity(0.06)
      ..style = PaintingStyle.fill;
    final fillPath = Path();
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, 60);
    fillPath.quadraticBezierTo(size.width * 0.4, 90, size.width * 0.5, 70);
    fillPath.quadraticBezierTo(size.width * 0.65, 50, size.width, 80);
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
