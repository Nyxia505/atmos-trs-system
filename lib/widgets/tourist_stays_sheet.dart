import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/screens/establishment_stay_pending_screen.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';

/// Tourist list of establishment stay requests + receipts.
class TouristStaysSheet extends StatelessWidget {
  const TouristStaysSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TouristStaysSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final height = MediaQuery.sizeOf(context).height * 0.72;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Establishment stays',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Hotel / AE QR scans wait for front-desk confirmation, then become receipts here.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.35),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: uid.isEmpty
                ? const Center(child: Text('Sign in to see stays.'))
                : StreamBuilder<List<EstablishmentStayRequest>>(
                    stream: EstablishmentStayService.watchForTourist(uid),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(child: Text('Error: ${snap.error}'));
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final stays = snap.data!;
                      if (stays.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No establishment stays yet.\nScan a hotel QR to start.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: stays.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final s = stays[i];
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              title: Text(
                                s.establishmentName,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                s.isPending
                                    ? 'Waiting for front desk'
                                    : s.isConfirmed
                                        ? 'Confirmed · ${s.nightsStayed ?? 0} night(s) · ${s.roomsOccupied ?? 0} room(s)'
                                        : s.isCheckedOut
                                            ? 'Checked out · ${s.nightsStayed ?? 0} night(s)'
                                            : 'Rejected',
                              ),
                              trailing: Icon(
                                s.isConfirmed || s.isCheckedOut
                                    ? Icons.receipt_long_outlined
                                    : s.isPending
                                        ? Icons.hourglass_top_rounded
                                        : Icons.cancel_outlined,
                                color: s.isCheckedOut
                                    ? const Color(0xFF2563EB)
                                    : s.isConfirmed
                                        ? const Color(0xFF059669)
                                        : AppTheme.brandOrange,
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                if (s.isConfirmed || s.isCheckedOut) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          EstablishmentStayReceiptScreen(stay: s),
                                    ),
                                  );
                                } else {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          EstablishmentStayPendingScreen(
                                        stayId: s.id,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
