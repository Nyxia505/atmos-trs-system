import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/screens/qr_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Tourist QR preview card on the profile tab.
class ProfileTouristQrCard extends StatelessWidget {
  const ProfileTouristQrCard({
    super.key,
    required this.profile,
    required this.touristId,
  });

  final UserProfile? profile;
  final String touristId;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;
    final name = profile?.fullName ?? 'Guest';
    final location = profile?.fullAddress.isNotEmpty == true
        ? profile!.fullAddress
        : (profile?.city ?? 'Misamis Occidental');
    final qrData = touristId != '—'
        ? QrProfileScreen.buildTouristQrData(touristId)
        : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: accent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Tourist QR ID',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              if (qrData.isNotEmpty)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => QrProfileScreen(
                          touristId: touristId,
                          fullName: name,
                          location: location,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (qrData.isEmpty)
            const Text(
              'Sign in to generate your tourist QR.',
              style: TextStyle(color: Color(0xFF6B7280)),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 160,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: accent,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
