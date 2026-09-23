import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/establishment_stay_review_service.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';

/// Required post-checkout hotel + room ratings (optional comment).
/// Room number is auto-included from the confirmed stay (lodging).
class WriteEstablishmentStayReviewSheet extends StatefulWidget {
  const WriteEstablishmentStayReviewSheet({
    super.key,
    required this.stay,
    this.requireBeforeClose = true,
  });

  final EstablishmentStayRequest stay;
  final bool requireBeforeClose;

  static Future<bool> show(
    BuildContext context, {
    required EstablishmentStayRequest stay,
    bool requireBeforeClose = true,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: !requireBeforeClose,
      enableDrag: !requireBeforeClose,
      backgroundColor: Colors.transparent,
      builder: (_) => WriteEstablishmentStayReviewSheet(
        stay: stay,
        requireBeforeClose: requireBeforeClose,
      ),
    );
    return result == true;
  }

  @override
  State<WriteEstablishmentStayReviewSheet> createState() =>
      _WriteEstablishmentStayReviewSheetState();
}

class _WriteEstablishmentStayReviewSheetState
    extends State<WriteEstablishmentStayReviewSheet> {
  double _hotel = 0;
  double _room = 0;
  final _commentCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lodging =
        EstablishmentCapability.isLodging(widget.stay.establishmentCategory);
    if (_hotel < 1) {
      setState(() => _error = 'Rate the establishment (1–5 stars).');
      return;
    }
    if (lodging && _room < 1) {
      setState(() => _error = 'Rate the room you stayed in (1–5 stars).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await EstablishmentStayReviewService.submitReview(
        stay: widget.stay,
        hotelRating: _hotel,
        roomRating: lodging ? _room : _hotel,
        comment: _commentCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final lodging =
        EstablishmentCapability.isLodging(widget.stay.establishmentCategory);
    final rooms = widget.stay.roomNumbers
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final roomLabel =
        rooms.isEmpty ? null : 'Room ${rooms.join(', ')}';
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Review your stay',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.stay.establishmentName,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
            ),
            if (lodging && roomLabel != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Auto-included: $roomLabel (from front-desk confirm)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ] else if (lodging && roomLabel == null) ...[
              const SizedBox(height: 6),
              Text(
                'No room number on this stay — desk should assign rooms at confirm.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ],
            const SizedBox(height: 18),
            _ratingRow(
              label: lodging ? 'Hotel / establishment' : 'Establishment',
              value: _hotel,
              onChanged: (v) => setState(() => _hotel = v),
            ),
            if (lodging) ...[
              const SizedBox(height: 12),
              _ratingRow(
                label: roomLabel == null
                    ? 'Your room'
                    : 'Your room ($roomLabel)',
                value: _room,
                onChanged: (v) => setState(() => _room = v),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit review'),
            ),
            if (!widget.requireBeforeClose) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text('Later'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ratingRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => onChanged(i.toDouble()),
                icon: Icon(
                  i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: AppTheme.brandOrange,
                  size: 32,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
