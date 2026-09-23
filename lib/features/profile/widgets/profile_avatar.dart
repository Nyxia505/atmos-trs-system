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
    this.onTap,
    this.showEditBadge = false,
    this.isBusy = false,
  });

  final UserProfile? profile;
  final double size;
  final double ringWidth;
  final Color? ringColor;
  final VoidCallback? onTap;
  final bool showEditBadge;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final accent = ringColor ?? AppTheme.primary;
    final avatar = Container(
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
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImage(),
            if (isBusy)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (onTap == null && !showEditBadge) return avatar;

    return GestureDetector(
      onTap: isBusy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          if (showEditBadge)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
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
