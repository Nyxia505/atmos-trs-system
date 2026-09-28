import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:atmos_trs_system/screens/establishment_stay_pending_screen.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/widgets/tourist_full_page.dart';

/// Tourist list of establishment stay requests + receipts (full-screen page).
class TouristStaysSheet extends StatelessWidget {
  const TouristStaysSheet({super.key});

  static Future<void> show(BuildContext context) {
    return pushTouristFullPage<void>(context, const TouristStaysSheet());
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return TouristFullPage(
      title: 'My hotel stays',
      subtitle: 'Hotel QR scans wait for front-desk confirmation, '
          'then become receipts here.',
      icon: Icons.hotel_rounded,
      child: uid.isEmpty
          ? const TouristEmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Sign in to see stays',
              message: 'Your hotel stays and receipts appear here once you log in.',
            )
          : StreamBuilder<List<EstablishmentStayRequest>>(
              stream: EstablishmentStayService.watchForTourist(uid),
              builder: (context, snap) {
                if (snap.hasError) {
                  return TouristEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could not load stays',
                    message: '${snap.error}',
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final stays = snap.data!;
                if (stays.isEmpty) {
                  return const TouristEmptyState(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'No hotel stays yet',
                    message: 'Scan a hotel’s QR code at the front desk to '
                        'start your stay.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  itemCount: stays.length + 1,
                  separatorBuilder: (_, i) =>
                      SizedBox(height: i == 0 ? 12 : 10),
                  itemBuilder: (context, i) {
                    if (i == 0) return _SummaryRow(stays: stays);
                    return _StayCard(stay: stays[i - 1]);
                  },
                );
              },
            ),
    );
  }
}

class _StayVisual {
  const _StayVisual(this.label, this.icon, this.fg, this.bg);
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;

  static _StayVisual of(EstablishmentStayRequest s) {
    if (s.isPending) {
      return const _StayVisual(
        'Waiting',
        Icons.hourglass_top_rounded,
        Color(0xFFC2410C),
        Color(0xFFFFEDD5),
      );
    }
    if (s.isConfirmed) {
      return const _StayVisual(
        'Confirmed',
        Icons.verified_rounded,
        Color(0xFF15803D),
        Color(0xFFDCFCE7),
      );
    }
    if (s.isCheckedOut) {
      return const _StayVisual(
        'Checked out',
        Icons.luggage_rounded,
        Color(0xFF1D4ED8),
        Color(0xFFDBEAFE),
      );
    }
    return const _StayVisual(
      'Rejected',
      Icons.cancel_rounded,
      Color(0xFFB91C1C),
      Color(0xFFFEE2E2),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.stays});
  final List<EstablishmentStayRequest> stays;

  @override
  Widget build(BuildContext context) {
    final waiting = stays.where((s) => s.isPending).length;
    final active = stays.where((s) => s.isConfirmed).length;
    final done = stays.where((s) => s.isCheckedOut).length;
    return Row(
      children: [
        _stat('Waiting', waiting, const Color(0xFFC2410C)),
        const SizedBox(width: 10),
        _stat('Confirmed', active, const Color(0xFF15803D)),
        const SizedBox(width: 10),
        _stat('Checked out', done, const Color(0xFF1D4ED8)),
      ],
    );
  }

  Widget _stat(String label, int n, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Text(
              '$n',
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StayCard extends StatelessWidget {
  const _StayCard({required this.stay});
  final EstablishmentStayRequest stay;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String? get _dateLabel {
    final d = stay.checkInAt ?? stay.confirmedAt ?? stay.createdAt;
    if (d == null) return null;
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  void _open(BuildContext context) {
    final page = stay.isConfirmed || stay.isCheckedOut
        ? EstablishmentStayReceiptScreen(stay: stay)
        : EstablishmentStayPendingScreen(stayId: stay.id);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final v = _StayVisual.of(stay);
    final nights = stay.nightsStayed ?? 0;
    final rooms = stay.roomNumbers.where((r) => r.trim().isNotEmpty).toList();
    final chips = <(IconData, String)>[
      if (_dateLabel != null) (Icons.event_rounded, _dateLabel!),
      if (!stay.isPending && nights > 0)
        (Icons.bedtime_rounded, '$nights ${nights == 1 ? 'night' : 'nights'}'),
      if (rooms.isNotEmpty) (Icons.meeting_room_rounded, 'Room ${rooms.join(', ')}'),
      if (stay.isPending) (Icons.schedule_rounded, 'Show your screen to the front desk'),
    ];

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: v.bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(v.icon, color: v.fg, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            stay.establishmentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: v.bg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            v.label,
                            style: TextStyle(
                              color: v.fg,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (stay.municipality.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        stay.municipality,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          for (final c in chips)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  c.$1,
                                  size: 14,
                                  color: const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  c.$2,
                                  style: const TextStyle(
                                    color: Color(0xFF475569),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
