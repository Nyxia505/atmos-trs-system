import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';
import 'package:atmos_trs_system/widgets/establishment_location_capture.dart';

/// Cards for the establishment "QR & profile" tab.

/// Peach hero with the live establishment QR, downloads and scan artwork.
class EstablishmentQrHero extends StatelessWidget {
  const EstablishmentQrHero({
    super.key,
    required this.payload,
    required this.hint,
    required this.onDownloadPng,
    required this.onDownloadPdf,
    this.flush = false,
  });

  static const String artAsset = 'assets/images/ae_qr_scan_phone.png';

  final String? payload;
  final String hint;
  final VoidCallback onDownloadPng;
  final VoidCallback onDownloadPdf;

  /// Edge-to-edge banner: square corners, bottom border only.
  final bool flush;

  @override
  Widget build(BuildContext context) {
    final qrBox = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AeDashTokens.accent, width: 2),
        boxShadow: AeDashTokens.softShadow,
      ),
      child: payload == null
          ? const SizedBox(
              width: 150,
              height: 150,
              child: Center(
                child: Icon(Icons.qr_code_2_rounded,
                    size: 64, color: AeDashTokens.muted),
              ),
            )
          : QrImageView(
              data: payload!,
              size: 150,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
            ),
    );
    final buttons = Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: onDownloadPng,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download PNG'),
          style: FilledButton.styleFrom(
            backgroundColor: AeDashTokens.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AeDashTokens.body(
              size: 13.5,
              color: Colors.white,
              weight: FontWeight.w700,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onDownloadPdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('Download PDF'),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AeDashTokens.accent,
            side: const BorderSide(color: AeDashTokens.accent, width: 1.4),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AeDashTokens.body(
              size: 13.5,
              color: AeDashTokens.accent,
              weight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 860;
        final artWidth = c.maxWidth * 0.32;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: flush ? null : BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
            ),
            border: flush
                ? const Border(bottom: BorderSide(color: Color(0xFFFED7AA)))
                : Border.all(color: const Color(0xFFFED7AA)),
            boxShadow: flush ? null : AeDashTokens.softShadow,
          ),
          child: wide
              ? Stack(
                  children: [
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: artWidth,
                      child: IgnorePointer(
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (rect) => const LinearGradient(
                            colors: [Colors.transparent, Colors.black],
                            stops: [0.0, 0.3],
                          ).createShader(rect),
                          child: Image.asset(
                            artAsset,
                            fit: BoxFit.cover,
                            alignment: Alignment.centerRight,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: artWidth * 0.5,
                      bottom: 20,
                      child: const _ScanChip(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(26, 24, 0, 24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _header(compact: false),
                                const SizedBox(height: 26),
                                buttons,
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          qrBox,
                          SizedBox(width: artWidth),
                        ],
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(compact: true),
                      const SizedBox(height: 18),
                      Center(child: qrBox),
                      const SizedBox(height: 18),
                      buttons,
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _header({required bool compact}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 46 : 56,
          height: compact ? 46 : 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AeDashTokens.softShadow,
          ),
          child: Icon(Icons.qr_code_2_rounded,
              color: AeDashTokens.accent, size: compact ? 24 : 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your establishment QR',
                style: AeDashTokens.heading(size: compact ? 20 : 24),
              ),
              const SizedBox(height: 4),
              Text(hint, style: AeDashTokens.body(size: 13.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScanChip extends StatelessWidget {
  const _ScanChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: AeDashTokens.softShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.qr_code_scanner_rounded,
              size: 15, color: AeDashTokens.accent),
          const SizedBox(width: 6),
          Text(
            'Scan to request a stay',
            style: AeDashTokens.body(
              size: 12,
              color: AeDashTokens.text,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Map pin card wrapping [EstablishmentLocationCapture] in dashboard style.
class EstablishmentMapPinCard extends StatelessWidget {
  const EstablishmentMapPinCard({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.locating,
    required this.saving,
    required this.onBusyChanged,
    required this.onChanged,
  });

  final double? latitude;
  final double? longitude;
  final bool locating;
  final bool saving;
  final ValueChanged<bool> onBusyChanged;
  final ValueChanged<({double latitude, double longitude})> onChanged;

  @override
  Widget build(BuildContext context) {
    return AePanelCard(
      title: 'Map pin',
      subtitle:
          'Tourists see your establishment on Explore after OPTACA approval. '
          'Stand at the entrance, then tap Get location.',
      icon: Icons.location_on_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EstablishmentLocationCapture(
            latitude: latitude,
            longitude: longitude,
            busy: locating,
            required: false,
            dashboardStyle: true,
            accentColor: AeDashTokens.accent,
            onBusyChanged: onBusyChanged,
            onChanged: onChanged,
          ),
          if (saving) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}

/// Profile photo gallery: dashed upload tile, real previews, empty collage.
class EstablishmentPhotosCard extends StatelessWidget {
  const EstablishmentPhotosCard({
    super.key,
    required this.urls,
    required this.maxImages,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  static const String collageAsset = 'assets/images/ae_photos_collage.png';

  final List<String> urls;
  final int maxImages;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  bool get _canAdd => urls.length < maxImages;

  @override
  Widget build(BuildContext context) {
    return AePanelCard(
      title: 'Profile photos',
      subtitle: 'Shown when tourists open your pin on Explore. '
          'Up to $maxImages photos.',
      icon: Icons.photo_library_rounded,
      child: LayoutBuilder(
        builder: (context, c) {
          if (urls.isEmpty) {
            final helper = Text(
              'No photos yet? Add your entrance, rooms, or amenities.',
              style: AeDashTokens.body(size: 13, color: AeDashTokens.subtitle),
            );
            if (c.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [helper, const SizedBox(height: 12), _uploadTile()],
              );
            }
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      helper,
                      const SizedBox(height: 12),
                      _uploadTile(),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 4,
                  child: IgnorePointer(
                    child: Image.asset(
                      collageAsset,
                      height: 180,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            );
          }
          final tile = c.maxWidth < 420 ? (c.maxWidth - 12) / 2 : 150.0;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < urls.length; i++) _thumb(i, tile),
              if (_canAdd || busy) _uploadTile(width: tile, height: tile),
            ],
          );
        },
      ),
    );
  }

  Widget _uploadTile({double? width, double height = 150}) {
    final canAdd = _canAdd;
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (!canAdd || busy) ? null : onAdd,
          borderRadius: BorderRadius.circular(14),
          child: AeDashedBox(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AeDashTokens.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AeDashTokens.accent,
                            ),
                          )
                        : const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: AeDashTokens.accent,
                            size: 23,
                          ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    busy
                        ? 'Uploading…'
                        : canAdd
                            ? 'Add photo'
                            : 'Photo limit reached',
                    style: AeDashTokens.section(
                      size: 14,
                      color: canAdd ? AeDashTokens.accent : AeDashTokens.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'PNG, JPG up to $maxImages photos',
                    textAlign: TextAlign.center,
                    style: AeDashTokens.body(size: 11.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb(int i, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              urls[i],
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: size,
                height: size,
                color: const Color(0xFFE2E8F0),
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : () => onRemove(i),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
          if (i == 0)
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AeDashTokens.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Cover',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Check-in / check-out time pickers as dropdown-style fields.
class EstablishmentHoursCard extends StatelessWidget {
  const EstablishmentHoursCard({
    super.key,
    required this.checkInLabel,
    required this.checkOutLabel,
    required this.saving,
    required this.onPickCheckIn,
    required this.onPickCheckOut,
  });

  /// e.g. "2:00 PM"; null when unset.
  final String? checkInLabel;
  final String? checkOutLabel;
  final bool saving;
  final VoidCallback onPickCheckIn;
  final VoidCallback onPickCheckOut;

  @override
  Widget build(BuildContext context) {
    final checkIn = AeSelectField(
      icon: Icons.login_rounded,
      label: 'Check-in time',
      value: checkInLabel == null ? 'Not set' : 'In $checkInLabel',
      onTap: saving ? null : onPickCheckIn,
    );
    final checkOut = AeSelectField(
      icon: Icons.logout_rounded,
      label: 'Check-out time',
      value: checkOutLabel == null ? 'Not set' : 'Out $checkOutLabel',
      onTap: saving ? null : onPickCheckOut,
      iconColor: AeDashTokens.chartSecondary,
    );
    return AePanelCard(
      title: 'Check-in / check-out times',
      subtitle: 'Guests arriving before check-in may be charged an extra night. '
          'Checkout is due by the check-out time on their last day.',
      icon: Icons.schedule_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 440) {
                return Column(
                  children: [checkIn, const SizedBox(height: 10), checkOut],
                );
              }
              return Row(
                children: [
                  Expanded(child: checkIn),
                  const SizedBox(width: 12),
                  Expanded(child: checkOut),
                ],
              );
            },
          ),
          if (saving) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}

/// Total rooms input + Save.
class EstablishmentRoomCountCard extends StatelessWidget {
  const EstablishmentRoomCountCard({
    super.key,
    required this.controller,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AeDashTokens.border),
    );
    return AePanelCard(
      title: 'Total rooms',
      subtitle: 'Defines Room 1–N for the Rooms grid and occupancy. '
          'Changes require confirmation and cannot drop below occupied rooms.',
      icon: Icons.meeting_room_rounded,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: AeDashTokens.section(size: 15),
              decoration: InputDecoration(
                labelText: 'Room count',
                labelStyle: AeDashTokens.body(size: 13),
                prefixIcon: const Icon(Icons.bed_rounded,
                    color: AeDashTokens.accent, size: 20),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                border: fieldBorder,
                enabledBorder: fieldBorder,
                focusedBorder: fieldBorder.copyWith(
                  borderSide:
                      const BorderSide(color: AeDashTokens.accent, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: saving ? null : onSave,
            style: FilledButton.styleFrom(
              backgroundColor: AeDashTokens.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: AeDashTokens.body(
                size: 14,
                color: Colors.white,
                weight: FontWeight.w700,
              ),
            ),
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
