import 'dart:async';

import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/establishment_stay_review.dart';
import 'package:atmos_trs_system/services/establishment_stay_review_service.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';
import 'package:atmos_trs_system/widgets/write_establishment_stay_review_sheet.dart';

/// Tourist waits here after scanning a hotel QR until front desk confirms.
class EstablishmentStayPendingScreen extends StatefulWidget {
  const EstablishmentStayPendingScreen({
    super.key,
    required this.stayId,
  });

  final String stayId;

  @override
  State<EstablishmentStayPendingScreen> createState() =>
      _EstablishmentStayPendingScreenState();
}

class _EstablishmentStayPendingScreenState
    extends State<EstablishmentStayPendingScreen> {
  StreamSubscription<EstablishmentStayRequest?>? _sub;
  EstablishmentStayRequest? _stay;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = EstablishmentStayService.watchStay(widget.stayId).listen(
      (stay) {
        if (!mounted) return;
        setState(() {
          _stay = stay;
          _error = stay == null ? 'Stay request not found.' : null;
        });
        if (stay != null && (stay.isConfirmed || stay.isCheckedOut)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => EstablishmentStayReceiptScreen(stay: stay),
              ),
            );
          });
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _error = 'Could not listen for front-desk confirmation.');
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stay = _stay;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: AppTheme.brandOrange,
        foregroundColor: Colors.white,
        title: const Text('Establishment stay'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _error != null
            ? Center(child: Text(_error!, textAlign: TextAlign.center))
            : stay == null
                ? const Center(child: CircularProgressIndicator())
                : stay.isRejected
                    ? _RejectedBody(stay: stay)
                    : _WaitingBody(stay: stay),
      ),
    );
  }
}

class _WaitingBody extends StatelessWidget {
  const _WaitingBody({required this.stay});
  final EstablishmentStayRequest stay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Icon(Icons.hourglass_top_rounded, size: 56, color: AppTheme.brandOrange),
        const SizedBox(height: 16),
        Text(
          'Waiting for front desk',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          stay.establishmentName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Please show this screen to the establishment staff. '
          'They will confirm your stay details on their ATMOS dashboard. '
          'This page updates automatically when they confirm.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Status', 'Pending confirmation'),
              _kv('Party size', '${stay.partySize}'),
              if (stay.municipality.isNotEmpty)
                _kv('Municipality', stay.municipality),
              _kv('Reference', stay.id),
            ],
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to app — keep waiting in Stays'),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectedBody extends StatelessWidget {
  const _RejectedBody({required this.stay});
  final EstablishmentStayRequest stay;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.cancel_outlined, size: 56, color: Color(0xFFB91C1C)),
        const SizedBox(height: 12),
        const Text(
          'Stay was not confirmed',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          stay.notes.isNotEmpty
              ? stay.notes
              : 'Front desk declined this request. You can scan again or ask staff for help.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Tourist receipt / history detail after staff confirms.
class EstablishmentStayReceiptScreen extends StatefulWidget {
  const EstablishmentStayReceiptScreen({super.key, required this.stay});

  final EstablishmentStayRequest stay;

  @override
  State<EstablishmentStayReceiptScreen> createState() =>
      _EstablishmentStayReceiptScreenState();
}

class _EstablishmentStayReceiptScreenState
    extends State<EstablishmentStayReceiptScreen> {
  late EstablishmentStayRequest _stay;
  StreamSubscription<EstablishmentStayRequest?>? _sub;
  EstablishmentStayReview? _review;
  StreamSubscription<EstablishmentStayReview?>? _reviewSub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _stay = widget.stay;
    _sub = EstablishmentStayService.watchStay(_stay.id).listen((s) {
      if (!mounted || s == null) return;
      setState(() => _stay = s);
      if (s.isCheckedOut && _review == null) {
        _promptReviewIfNeeded();
      }
    });
    _reviewSub =
        EstablishmentStayReviewService.watchForStay(_stay.id).listen((r) {
      if (!mounted) return;
      setState(() => _review = r);
    });
    if (_stay.isCheckedOut) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _promptReviewIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reviewSub?.cancel();
    super.dispose();
  }

  Future<void> _promptReviewIfNeeded() async {
    if (!mounted || _review != null || !_stay.isCheckedOut) return;
    await WriteEstablishmentStayReviewSheet.show(
      context,
      stay: _stay,
      requireBeforeClose: true,
    );
  }

  Future<void> _checkOut() async {
    setState(() => _busy = true);
    try {
      await EstablishmentStayService.checkOutStay(stayId: _stay.id);
      if (!mounted) return;
      final updated = await EstablishmentStayService.getStay(_stay.id);
      if (!mounted) return;
      if (updated != null) setState(() => _stay = updated);
      await WriteEstablishmentStayReviewSheet.show(
        context,
        stay: updated ?? _stay,
        requireBeforeClose: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Check-out failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stay = _stay;
    String fmt(DateTime? d) {
      if (d == null) return '—';
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    final inHouse = EstablishmentRoomGrid.isInHouse(stay);
    final headerColor = stay.isCheckedOut
        ? const Color(0xFFEFF6FF)
        : const Color(0xFFECFDF5);
    final headerBorder = stay.isCheckedOut
        ? const Color(0xFF93C5FD)
        : const Color(0xFF6EE7B7);
    final headerTitleColor = stay.isCheckedOut
        ? const Color(0xFF1E40AF)
        : const Color(0xFF065F46);
    final headerNameColor = stay.isCheckedOut
        ? const Color(0xFF1E3A8A)
        : const Color(0xFF064E3B);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: AppTheme.brandOrange,
        foregroundColor: Colors.white,
        title: const Text('Stay receipt'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: headerBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stay.isCheckedOut
                      ? 'Checked out'
                      : 'Confirmed by front desk',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: headerTitleColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  stay.establishmentName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: headerNameColor,
                  ),
                ),
              ],
            ),
          ),
          if (stay.isCheckedOut && _review == null) ...[
            const SizedBox(height: 12),
            Material(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                leading: Icon(Icons.rate_review_outlined,
                    color: Colors.orange.shade800),
                title: const Text(
                  'Leave a review of your stay',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Rate the hotel and your room.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () => WriteEstablishmentStayReviewSheet.show(
                          context,
                          stay: stay,
                          requireBeforeClose: true,
                        ),
              ),
            ),
          ],
          if (_review != null) ...[
            const SizedBox(height: 12),
            _card([
              _row(
                'Your ratings',
                'Hotel ${_review!.hotelRating.toStringAsFixed(0)}★ · '
                    'Room ${_review!.roomRating.toStringAsFixed(0)}★',
              ),
              if (_review!.comment.isNotEmpty)
                _row('Your comment', _review!.comment),
            ]),
          ],
          const SizedBox(height: 18),
          _card([
            _row('Reference', stay.id),
            _row('Guest', stay.touristName),
            _row('Party size', '${stay.partySize}'),
            if (stay.femaleCount + stay.maleCount > 0)
              _row('Male / Female', '${stay.maleCount} / ${stay.femaleCount}'),
            if (stay.filipinoCount + stay.foreignCount > 0)
              _row(
                'Filipino / Foreign',
                '${stay.filipinoCount} / ${stay.foreignCount}',
              ),
            if (stay.touristNationality.isNotEmpty)
              _row('Scanner nationality', stay.touristNationality),
            if (stay.touristCountry.isNotEmpty)
              _row('Scanner country', stay.touristCountry),
            _row('Nights stayed', '${stay.nightsStayed ?? '—'}'),
            _row('Rooms occupied', '${stay.roomsOccupied ?? '—'}'),
            if (stay.roomNumbers.isNotEmpty)
              _row('Room numbers', stay.roomNumbers.join(', ')),
            _row('Check-in', fmt(stay.checkInAt)),
            _row(
              stay.isCheckedOut ? 'Planned check-out' : 'Check-out',
              fmt(stay.checkOutAt),
            ),
            if (stay.checkedOutAt != null)
              _row('Checked out at', fmt(stay.checkedOutAt)),
            _row('Confirmed at', fmt(stay.confirmedAt)),
            if (stay.municipality.isNotEmpty)
              _row('Municipality', stay.municipality),
            if (stay.notes.isNotEmpty) _row('Notes', stay.notes),
          ]),
          const SizedBox(height: 20),
          if (inHouse) ...[
            FilledButton(
              onPressed: _busy ? null : _checkOut,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Check out & review'),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            style: FilledButton.styleFrom(
              backgroundColor:
                  inHouse ? const Color(0xFF64748B) : AppTheme.brandOrange,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(children: children),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              k,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
