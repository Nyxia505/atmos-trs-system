import 'dart:convert';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ProfileTouristQrCard extends StatelessWidget {
  const ProfileTouristQrCard({
    super.key,
    required this.profile,
    required this.touristId,
    this.compact = false,
    this.embedded = false,
  });

  final UserProfile? profile;
  final String touristId;
  final bool compact;
  final bool embedded;

  static String _qrPayload(String id) {
    return jsonEncode(<String, String>{
      'type': 'tourist',
      'tourist_id': id,
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;
    final id = touristId.trim().isNotEmpty
        ? touristId.trim()
        : (profile?.touristId ?? '').trim();
    final hasId = id.isNotEmpty;
    final qrSize = compact ? 112.0 : 148.0;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact)
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded, size: 18, color: accent),
              const SizedBox(width: 6),
              Text(
                'Tourist QR',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Show at check-in',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: accent.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          )
        else ...[
          Text(
            'Tourist QR',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Show at check-in or partner sites',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ],
        SizedBox(height: compact ? 8 : 16),
        if (hasId)
          Container(
            padding: EdgeInsets.all(compact ? 6 : 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(compact ? 10 : 12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: QrImageView(
              data: _qrPayload(id),
              version: QrVersions.auto,
              size: qrSize,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
            ),
          )
        else
          Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 12 : 24),
            child: const Text(
              'Tourist ID not available yet',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
          ),
      ],
    );

    if (embedded) return content;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: content,
    );
  }
}
