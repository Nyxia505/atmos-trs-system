import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/features/navigation/main_shell.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Firestore collection for tourist spots. Each doc should have:
/// municipalityId, name, category, description, and optionally vrTourUrl.
const String _kTouristSpotsCollection = 'tourist_spots';

/// Full-screen municipality details: fetches spots from Firestore by [municipalityId],
/// shows name, category, description per spot with QR actions.
class MunicipalityDetailsScreen extends StatelessWidget {
  const MunicipalityDetailsScreen({
    super.key,
    required this.municipalityId,
    required this.municipalityName,
  });

  final String municipalityId;
  final String municipalityName;

  static Stream<QuerySnapshot<Map<String, dynamic>>> _spotsStream(String municipalityId) {
    return FirebaseFirestore.instance
        .collection(_kTouristSpotsCollection)
        .where('municipalityId', isEqualTo: municipalityId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: AppTheme.scaffoldBackground,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                municipalityName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black45)],
                ),
              ),
              background: _HeaderPlaceholder(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tourist spots',
                    style: TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _spotsStream(municipalityId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _LoadingState();
                      }
                      if (snapshot.hasError) {
                        return _ErrorState(message: snapshot.error.toString());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return _EmptyState();
                      }
                      final spots = snapshot.data!.docs
                          .map((d) => TouristSpot.fromFirestore(d.data(), d.id))
                          .toList()
                        ..sort((a, b) => a.name.compareTo(b.name));
                      return Column(
                        children: spots
                            .map((spot) => _SpotCard(
                                  spot: spot,
                                  municipalityId: municipalityId,
                                  onScanQr: () => _navigateToScan(context),
                                  onShowQr: () => _showSpotQrDialog(context, spot, municipalityId),
                                ))
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToScan(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => MainShell(initialIndex: 2),
      ),
      (route) => false,
    );
  }

  void _showSpotQrDialog(BuildContext context, TouristSpot spot, String municipalityId) {
    final qrData = spotQrData(municipalityId, spot.id);
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                spot.name,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Spot QR Code – Print or screenshot for registration',
                style: TextStyle(
                  color: AppTheme.unselectedMuted,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
          Icons.landscape,
          size: 64,
          color: AppTheme.unselectedMuted.withOpacity(0.5),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(
              'Loading spots…',
              style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.place_outlined, size: 56, color: AppTheme.unselectedMuted.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text(
              'No tourist spots yet',
              style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Spots will appear here when added in Firestore.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.unselectedMuted.withOpacity(0.8), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.unselectedMuted.withOpacity(0.8), fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({
    required this.spot,
    required this.municipalityId,
    required this.onScanQr,
    required this.onShowQr,
  });

  final TouristSpot spot;
  final String municipalityId;
  final VoidCallback onScanQr;
  final VoidCallback onShowQr;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconForCategory(spot.category), color: AppTheme.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.name,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _CategoryChip(label: spot.category),
                  ],
                ),
              ),
            ],
          ),
          if (spot.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              spot.description,
              style: TextStyle(
                color: AppTheme.unselectedMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShowQr,
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: const Text('Show QR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onScanQr,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan QR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: AppTheme.unselectedMuted.withOpacity(0.5)),
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

  IconData _iconForCategory(String category) {
    final c = category.toLowerCase();
    if (c.contains('beach') || c.contains('water')) return Icons.waves_rounded;
    if (c.contains('mountain') || c.contains('nature')) return Icons.terrain_rounded;
    if (c.contains('heritage') || c.contains('plaza')) return Icons.account_balance_rounded;
    if (c.contains('festival')) return Icons.celebration_rounded;
    return Icons.place_rounded;
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

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
        style: TextStyle(
          color: AppTheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
