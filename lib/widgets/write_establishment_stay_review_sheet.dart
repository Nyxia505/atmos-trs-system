import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/establishment_stay_review_service.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/widgets/tourist_full_page.dart';

/// Required post-checkout hotel + room ratings (optional comment).
/// Room number is auto-included from the confirmed stay (lodging).
class WriteEstablishmentStayReviewSheet extends StatefulWidget {
  const WriteEstablishmentStayReviewSheet({
    super.key,
    required this.stay,
    this.requireBeforeClose = true,
    this.fullPage = false,
  });

  final EstablishmentStayRequest stay;
  final bool requireBeforeClose;

  /// Mobile: full-screen page with back button instead of a bottom sheet.
  final bool fullPage;

  /// App-wide, so stacked receipt screens for one stay never open two forms.
  static final Set<String> _openFor = {};
  static final Set<String> _submittedFor = {};

  static Future<bool> show(
    BuildContext context, {
    required EstablishmentStayRequest stay,
    bool requireBeforeClose = true,
  }) async {
    final id = stay.id;
    if (_openFor.contains(id) || _submittedFor.contains(id)) return false;
    _openFor.add(id);
    try {
      final bool? result;
      if (MediaQuery.sizeOf(context).width < 600) {
        result = await pushTouristFullPage<bool>(
          context,
          WriteEstablishmentStayReviewSheet(stay: stay, fullPage: true),
        );
      } else {
        result = await showModalBottomSheet<bool>(
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
      }
      if (result == true) _submittedFor.add(id);
      return result == true;
    } finally {
      _openFor.remove(id);
    }
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
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    if (widget.fullPage) {
      return TouristFullPage(
        title: 'Rate your stay',
        subtitle: widget.stay.establishmentName,
        icon: Icons.reviews_rounded,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 24 + safeBottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPageIntro(lodging, roomLabel),
              const SizedBox(height: 16),
              ..._buildForm(lodging, roomLabel),
            ],
          ),
        ),
      );
    }

    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: const BoxDecoration(
            color: _kSheetBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + safeBottom),
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
                const SizedBox(height: 18),
                _buildHeader(lodging, roomLabel),
                const SizedBox(height: 18),
                ..._buildForm(lodging, roomLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildForm(bool lodging, String? roomLabel) {
    return [
                _ratingCard(
                  icon: Icons.apartment_rounded,
                  label: lodging ? 'The hotel' : 'The establishment',
                  hint: 'Service, cleanliness, staff',
                  value: _hotel,
                  onChanged: (v) => setState(() {
                    _hotel = v;
                    _error = null;
                  }),
                ),
                if (lodging) ...[
                  const SizedBox(height: 12),
                  _ratingCard(
                    icon: Icons.king_bed_rounded,
                    label: roomLabel == null ? 'Your room' : 'Your room · $roomLabel',
                    hint: 'Comfort, amenities, condition',
                    value: _room,
                    onChanged: (v) => setState(() {
                      _room = v;
                      _error = null;
                    }),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _commentCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Tell others about your stay (optional)',
                    hintStyle: const TextStyle(color: _kMuted, fontSize: 14),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _kBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: AppTheme.brandOrange,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: Color(0xFFB91C1C),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFB91C1C),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 19),
                  label: const Text('Submit review'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandOrange,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.fullPage || !widget.requireBeforeClose) ...[
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(foregroundColor: _kMuted),
                    child: const Text('Maybe later'),
                  ),
                ],
    ];
  }

  /// Full-page intro card: question, hotel and auto-filled room.
  Widget _buildPageIntro(bool lodging, String? roomLabel) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.brandOrange.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.hotel_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How was your stay?',
                  style: TextStyle(
                    color: _kInk,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  lodging && roomLabel != null
                      ? '$roomLabel · added by the front desk'
                      : 'Your rating helps other travelers.',
                  style: const TextStyle(
                    color: _kMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool lodging, String? roomLabel) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.brandOrange.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.reviews_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'How was your stay?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _kInk,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.stay.establishmentName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _kMuted,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (lodging && roomLabel != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.meeting_room_rounded,
                  size: 15,
                  color: Color(0xFFC2410C),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$roomLabel · added by the front desk',
                    style: const TextStyle(
                      color: Color(0xFF9A3412),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (lodging && roomLabel == null) ...[
          const SizedBox(height: 8),
          Text(
            'No room number on this stay — desk should assign rooms at confirm.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
          ),
        ],
      ],
    );
  }

  static const _ratingWords = ['Tap a star to rate', 'Terrible', 'Poor', 'Okay', 'Good', 'Excellent!'];

  Widget _ratingCard({
    required IconData icon,
    required String label,
    required String hint,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final rated = value >= 1;
    final idx = value.round().clamp(0, 5);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: rated ? const Color(0xFFFDBA74) : _kBorder,
          width: rated ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: const Color(0xFFC2410C)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: _kInk,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      hint,
                      style: const TextStyle(color: _kMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => onChanged(i.toDouble()),
                  tooltip: _ratingWords[i],
                  icon: AnimatedScale(
                    scale: i <= value ? 1.12 : 1.0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      i <= value
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: i <= value
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFCBD5E1),
                      size: 38,
                    ),
                  ),
                ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              _ratingWords[idx],
              key: ValueKey(idx),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: rated ? const Color(0xFFC2410C) : _kMuted,
                fontSize: 13,
                fontWeight: rated ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const Color _kSheetBg = Color(0xFFF8FAFC);
const Color _kInk = Color(0xFF0F172A);
const Color _kMuted = Color(0xFF64748B);
const Color _kBorder = Color(0xFFE2E8F0);
