import 'dart:convert';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    this.size = 72,
    this.ringWidth = 3,
    this.ringColor,
  });

  final UserProfile? profile;
  final double size;
  final double ringWidth;
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final accent = ringColor ?? AppTheme.primary;
    return Container(
      width: size + ringWidth * 2,
      height: size + ringWidth * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: ringWidth),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(child: _buildImage()),
    );
  }

  Widget _buildImage() {
    final url = profile?.profilePhotoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildMemoryOrPlaceholder(),
      );
    }
    return _buildMemoryOrPlaceholder();
  }

  Widget _buildMemoryOrPlaceholder() {
    final b64 = profile?.profileImageBase64;
    if (b64 != null && b64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(b64),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      } catch (_) {
        return _placeholder();
      }
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFF3F4F6),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.45,
        color: const Color(0xFF9CA3AF),
      ),
    );
  }
}
