import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';

/// Municipality details screen for Sapang Dalaga: header, description, tourist spots.
/// Dark theme with orange accent (#F97316).
class SapangDalagaDetailsScreen extends StatelessWidget {
  const SapangDalagaDetailsScreen({super.key});

  static const String _title = 'Sapang Dalaga';
  static const String _description =
      'Sapang Dalaga is a coastal municipality in Misamis Occidental known for its natural attractions, '
      'plaza, and scenic views. Explore waterfalls, town landmarks, and nature spots.';

  static const List<_TouristSpot> _spots = [
    _TouristSpot(
      name: 'Sapang Dalaga Falls',
      category: 'Falls',
      icon: Icons.water_drop_rounded,
    ),
    _TouristSpot(
      name: 'Sapang Dalaga Plaza',
      category: 'Heritage',
      icon: Icons.account_balance_rounded,
    ),
    _TouristSpot(
      name: 'Sapang Dalaga Nature View',
      category: 'Mountains',
      icon: Icons.terrain_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppTheme.scaffoldBackground,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black45)],
                ),
              ),
              background: _buildHeaderPlaceholder(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _description,
                    style: TextStyle(
                      color: AppTheme.unselectedMuted,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Tourist spots',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ..._spots.map((spot) => _SpotCard(spot: spot)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderPlaceholder() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.cardBackground,
            AppTheme.scaffoldBackground,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 64,
          color: AppTheme.unselectedMuted.withOpacity(0.5),
        ),
      ),
    );
  }
}

class _TouristSpot {
  const _TouristSpot({
    required this.name,
    required this.category,
    required this.icon,
  });

  final String name;
  final String category;
  final IconData icon;
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({required this.spot});

  final _TouristSpot spot;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(spot.icon, color: AppTheme.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  spot.name,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              _CategoryChip(label: spot.category),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.explore, size: 18),
                  label: const Text('Explore'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: BorderSide(color: AppTheme.unselectedMuted.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openVrTour(context),
                  icon: const Icon(Icons.vrpano_rounded, size: 18),
                  label: const Text('View VR Tour'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openVrTour(BuildContext context) {
    openVrTour(context, url: kVrTourUrl, title: spot.name);
  }
}

class _CategoryChip extends StatelessWidget {
  _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
