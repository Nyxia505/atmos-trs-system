import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';

/// Placeholder for "Practice Scan" flow (QR scanner will be wired here later).
class ScanPracticePage extends StatelessWidget {
  const ScanPracticePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('Practice Scan'),
        backgroundColor: AppTheme.scaffoldBackground,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.qr_code_scanner_rounded,
              size: 80,
              color: AppTheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Scanner UI will go here',
              style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
