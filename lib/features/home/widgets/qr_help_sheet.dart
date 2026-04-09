import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/features/scan/scan_practice_page.dart';

/// Opens QR help as bottom sheet (mobile, width < 700) or dialog (web/tablet).
void openQrHelp(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 700) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              controller: scrollController,
              child: QrHelpSheet(
                onPracticeScan: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ScanPracticePage(),
                    ),
                  );
                },
                onClose: () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
        ),
      ),
    );
  } else {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                child: QrHelpSheet(
                  onPracticeScan: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ScanPracticePage(),
                      ),
                    );
                  },
                  onClose: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal content: "How to scan QR code for entry" with steps, LIVE EXAMPLE card, and actions.
class QrHelpSheet extends StatelessWidget {
  const QrHelpSheet({
    super.key,
    required this.onPracticeScan,
    required this.onClose,
  });

  final VoidCallback onPracticeScan;
  final VoidCallback onClose;

  static const _radius = 20.0;
  static const _steps = [
    'Locate the QR stand at the entrance',
    'Tap the orange scan button in your header',
    'Align the code within the camera frame',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTitleRow(),
          const SizedBox(height: 24),
          _buildStepList(),
          const SizedBox(height: 24),
          _buildLiveExampleCard(),
          const SizedBox(height: 28),
          _buildPracticeScanButton(),
          const SizedBox(height: 12),
          _buildGotItButton(),
        ],
      ),
    );
  }

  Widget _buildTitleRow() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.info_outline, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'How to scan QR code for entry',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_steps.length, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i < _steps.length - 1 ? 16 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _steps[i],
                    style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.unselectedMuted,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildLiveExampleCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBackground,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              'https://images.unsplash.com/photo-1586281380349-632531db7ed4?w=120',
              width: 88,
              height: 88,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 88,
                height: 88,
                color: AppTheme.cardBackground,
                child: Icon(Icons.qr_code_scanner, color: AppTheme.primary, size: 40),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'LIVE EXAMPLE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Keep your phone steady for 2 seconds to auto-verify.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.unselectedMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primary),
                ),
                child: Icon(Icons.qr_code_scanner_rounded, size: 20, color: AppTheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPracticeScanButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPracticeScan,
        icon: const Icon(Icons.bolt, color: Colors.white, size: 20),
        label: const Text('Practice Scan'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildGotItButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onClose,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primary,
          side: BorderSide(color: AppTheme.primary.withOpacity(0.7)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
        child: const Text('Got it, thanks!'),
      ),
    );
  }
}
