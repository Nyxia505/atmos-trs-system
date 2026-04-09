import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';

/// Top app bar: avatar + welcome text + QR button. Asenso dark theme.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    this.userName = 'Alex',
    this.onQrTap,
  });

  final String userName;
  final VoidCallback? onQrTap;

  @override
  Widget build(BuildContext context) {
    final padding = _paddingFor(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(padding, 12, padding, 16),
      decoration: const BoxDecoration(color: AppTheme.scaffoldBackground),
      child: Row(
        children: [
          // Avatar with online dot
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: Icon(Icons.person, color: Colors.white70, size: 28),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.scaffoldBackground, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.7),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  'Hi, $userName!',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onQrTap,
              borderRadius: BorderRadius.circular(12),
                child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double _paddingFor(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1100) return 48;
    if (width >= 600) return 32;
    return 20;
  }
}
