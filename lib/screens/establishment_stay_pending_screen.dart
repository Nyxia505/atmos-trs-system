import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/establishment_stay_review.dart';
import 'package:atmos_trs_system/services/establishment_stay_review_service.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
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
  bool _openedReceipt = false;

  @override
  void initState() {
    super.initState();
    _sub = EstablishmentStayService.watchStay(widget.stayId).listen(
      (stay) {
        if (!mounted || _openedReceipt) return;
        setState(() {
          _stay = stay;
          _error = stay == null ? 'Stay request not found.' : null;
        });
        if (stay != null && (stay.isConfirmed || stay.isCheckedOut)) {
          _openedReceipt = true;
          _sub?.cancel();
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
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: AppTheme.brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Establishment stay'),
      ),
      body: _error != null
          ? _MessageBody(
              icon: Icons.cloud_off_rounded,
              color: const Color(0xFF64748B),
              title: 'Something went wrong',
              message: _error!,
            )
          : stay == null
              ? const Center(child: CircularProgressIndicator())
              : stay.isRejected
                  ? _RejectedBody(stay: stay)
                  : _WaitingBody(stay: stay),
    );
  }
}

const Color _kPageBg = Color(0xFFF8FAFC);
const Color _kInk = Color(0xFF0F172A);
const Color _kMuted = Color(0xFF64748B);
const Color _kBorder = Color(0xFFE2E8F0);

String _timeAgo(DateTime? at) {
  if (at == null) return 'Just now';
  final diff = DateTime.now().difference(at);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} hr${diff.inHours == 1 ? '' : 's'} ago';
  }
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}

class _WaitingBody extends StatefulWidget {
  const _WaitingBody({required this.stay});
  final EstablishmentStayRequest stay;

  @override
  State<_WaitingBody> createState() => _WaitingBodyState();
}

class _WaitingBodyState extends State<_WaitingBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _copyReference() async {
    await Clipboard.setData(ClipboardData(text: widget.stay.id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reference copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stay = widget.stay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            children: [
              _buildHero(stay),
              const SizedBox(height: 16),
              _buildShowStaffHint(),
              const SizedBox(height: 16),
              _buildProgress(stay),
              const SizedBox(height: 16),
              _buildDetails(stay),
            ],
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildHero(EstablishmentStayRequest stay) {
    final orange = AppTheme.brandOrange;
    final deep = Color.lerp(orange, Colors.black, 0.22)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [orange, deep],
        ),
        boxShadow: [
          BoxShadow(
            color: orange.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _LivePill(pulse: _pulse),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 108,
            height: 108,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = _pulse.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    for (final offset in const [0.0, 0.5])
                      Builder(builder: (_) {
                        final p = (t + offset) % 1.0;
                        return Container(
                          width: 64 + 44 * p,
                          height: 64 + 44 * p,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white
                                .withValues(alpha: 0.22 * (1 - p)),
                          ),
                        );
                      }),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: Transform.rotate(
                        angle: t < 0.5 ? 0 : (t - 0.5) * 2 * 3.14159,
                        child: Icon(
                          Icons.hourglass_top_rounded,
                          size: 32,
                          color: orange,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Waiting for front desk',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hotel_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    stay.establishmentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (stay.municipality.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.place_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 4),
                Text(
                  stay.municipality,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShowStaffHint() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.brandOrange.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.phone_iphone_rounded,
              color: AppTheme.brandOrange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Show this screen to the front desk',
                  style: TextStyle(
                    color: Color(0xFF9A3412),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Staff will confirm your stay on their ATMOS dashboard. '
                  'This page updates by itself once they do.',
                  style: TextStyle(
                    color: Color(0xFF7C2D12),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(EstablishmentStayRequest stay) {
    return _SectionCard(
      title: 'Progress',
      child: Column(
        children: [
          _StepRow(
            state: _StepState.done,
            title: 'QR scanned',
            subtitle: 'Request sent · ${_timeAgo(stay.createdAt)}',
          ),
          _StepRow(
            state: _StepState.active,
            title: 'Front desk confirming',
            subtitle: 'Staff are checking your stay details',
            pulse: _pulse,
          ),
          const _StepRow(
            state: _StepState.upcoming,
            title: 'Stay receipt ready',
            subtitle: 'Opens here automatically',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(EstablishmentStayRequest stay) {
    return _SectionCard(
      title: 'Request details',
      child: Column(
        children: [
          _DetailRow(
            icon: Icons.flag_rounded,
            label: 'Status',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Pending confirmation',
                style: TextStyle(
                  color: Color(0xFF92400E),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          _DetailRow(
            icon: Icons.groups_rounded,
            label: 'Party size',
            value: '${stay.partySize} '
                '${stay.partySize == 1 ? 'guest' : 'guests'}',
          ),
          if (stay.municipality.isNotEmpty)
            _DetailRow(
              icon: Icons.location_city_rounded,
              label: 'Municipality',
              value: stay.municipality,
            ),
          _DetailRow(
            icon: Icons.schedule_rounded,
            label: 'Requested',
            value: _timeAgo(stay.createdAt),
          ),
          _DetailRow(
            icon: Icons.tag_rounded,
            label: 'Reference',
            isLast: true,
            trailing: Flexible(
              child: InkWell(
                onTap: _copyReference,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          stay.id,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kInk,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.copy_rounded,
                        size: 16,
                        color: _kMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back to app'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.brandOrange,
              side: BorderSide(color: AppTheme.brandOrange, width: 1.4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your request keeps waiting. Find it anytime in Home › Stays.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.pulse});
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 1).animate(
              CurvedAnimation(parent: pulse, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF4ADE80),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: _kMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

enum _StepState { done, active, upcoming }

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.state,
    required this.title,
    required this.subtitle,
    this.pulse,
    this.isLast = false,
  });

  final _StepState state;
  final String title;
  final String subtitle;
  final Animation<double>? pulse;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF16A34A);
    final orange = AppTheme.brandOrange;
    final Widget dot = switch (state) {
      _StepState.done => Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: green,
          ),
          child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
        ),
      _StepState.active => SizedBox(
          width: 26,
          height: 26,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: orange,
                  backgroundColor: orange.withValues(alpha: 0.15),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: orange,
                ),
              ),
            ],
          ),
        ),
      _StepState.upcoming => Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: _kBorder, width: 2),
          ),
          child: const Icon(
            Icons.receipt_long_rounded,
            size: 13,
            color: _kMuted,
          ),
        ),
    };
    final lineColor = state == _StepState.done ? green : _kBorder;
    final titleColor = state == _StepState.upcoming ? _kMuted : _kInk;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              dot,
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: lineColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 3, bottom: isLast ? 8 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: state == _StepState.active ? orange : titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _kMuted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.brandOrange),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: _kMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          const Spacer(),
          if (trailing != null)
            trailing!
          else
            Flexible(
              flex: 3,
              child: Text(
                value ?? '',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.12),
                ),
                child: Icon(icon, size: 36, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kMuted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 22),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RejectedBody extends StatelessWidget {
  const _RejectedBody({required this.stay});
  final EstablishmentStayRequest stay;

  @override
  Widget build(BuildContext context) {
    return _MessageBody(
      icon: Icons.do_not_disturb_on_rounded,
      color: const Color(0xFFB91C1C),
      title: 'Stay was not confirmed',
      message: stay.notes.isNotEmpty
          ? stay.notes
          : 'The front desk at ${stay.establishmentName} declined this '
              'request. You can scan their QR again or ask staff for help.',
      action: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.brandOrange,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text('Back to app'),
        ),
      ),
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
  bool _reviewOpen = false;
  bool _reviewSubmitted = false;
  bool _autoPrompted = false;

  @override
  void initState() {
    super.initState();
    _stay = widget.stay;
    _sub = EstablishmentStayService.watchStay(_stay.id).listen((s) {
      if (!mounted || s == null) return;
      setState(() => _stay = s);
      if (s.isCheckedOut && _review == null && !_busy) {
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

  /// Auto-prompt at most once per screen; the receipt keeps a "Rate" card.
  Future<void> _promptReviewIfNeeded() async {
    if (_autoPrompted || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _autoPrompted = true;
    await _showReview();
  }

  /// Single entry point so the stay stream and check-out never stack sheets.
  Future<void> _showReview([EstablishmentStayRequest? stay]) async {
    if (!mounted ||
        _reviewOpen ||
        _reviewSubmitted ||
        _review != null ||
        !(stay ?? _stay).isCheckedOut) {
      return;
    }
    _reviewOpen = true;
    try {
      final submitted = await WriteEstablishmentStayReviewSheet.show(
        context,
        stay: stay ?? _stay,
        requireBeforeClose: true,
      );
      if (submitted && mounted) {
        setState(() => _reviewSubmitted = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks! Your review was submitted.')),
        );
      }
    } finally {
      _reviewOpen = false;
    }
  }

  Future<void> _checkOut() async {
    setState(() => _busy = true);
    try {
      await EstablishmentStayService.checkOutStay(stayId: _stay.id);
      if (!mounted) return;
      final updated = await EstablishmentStayService.getStay(_stay.id);
      if (!mounted) return;
      if (updated != null) setState(() => _stay = updated);
      _autoPrompted = true;
      if (mounted) setState(() => _busy = false);
      await _showReview(updated ?? _stay);
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
    final inHouse = EstablishmentRoomGrid.isInHouse(stay);
    final lodging = EstablishmentCapability.isLodging(stay.establishmentCategory);
    final review = _review;
    final checkedOutAt = stay.checkedOutAt;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        backgroundColor: AppTheme.brandOrange,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Stay receipt',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          _buildHero(stay, inHouse),
          if (stay.isCheckedOut && review == null && !_reviewSubmitted) ...[
            const SizedBox(height: 14),
            _buildReviewPrompt(),
          ],
          if (review != null) ...[
            const SizedBox(height: 14),
            _buildReviewCard(review, lodging),
          ],
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Timeline',
            child: Column(
              children: [
                _StepRow(
                  state: _StepState.done,
                  title: 'Confirmed by front desk',
                  subtitle: _fmt(stay.confirmedAt),
                ),
                _StepRow(
                  state: stay.checkInAt == null
                      ? _StepState.upcoming
                      : _StepState.done,
                  title: 'Checked in',
                  subtitle: _fmt(stay.checkInAt),
                ),
                _StepRow(
                  state: checkedOutAt != null
                      ? _StepState.done
                      : _StepState.upcoming,
                  title: checkedOutAt != null ? 'Checked out' : 'Check-out',
                  subtitle: checkedOutAt != null
                      ? '${_fmt(checkedOutAt)}\nPlanned: ${_fmt(stay.checkOutAt)}'
                      : 'Planned: ${_fmt(stay.checkOutAt)}',
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Guests',
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.person_rounded,
                  label: 'Guest',
                  value: stay.touristName.isEmpty ? '—' : stay.touristName,
                ),
                _DetailRow(
                  icon: Icons.groups_rounded,
                  label: 'Party size',
                  value: '${stay.partySize}',
                ),
                if (stay.femaleCount + stay.maleCount > 0)
                  _DetailRow(
                    icon: Icons.wc_rounded,
                    label: 'Male / Female',
                    value: '${stay.maleCount} / ${stay.femaleCount}',
                  ),
                if (stay.filipinoCount + stay.foreignCount > 0)
                  _DetailRow(
                    icon: Icons.public_rounded,
                    label: 'Filipino / Foreign',
                    value: '${stay.filipinoCount} / ${stay.foreignCount}',
                  ),
                if (stay.touristNationality.isNotEmpty)
                  _DetailRow(
                    icon: Icons.flag_rounded,
                    label: 'Nationality',
                    value: stay.touristNationality,
                  ),
                _DetailRow(
                  icon: Icons.language_rounded,
                  label: 'Country',
                  value: stay.touristCountry.isEmpty ? '—' : stay.touristCountry,
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Stay',
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.bedtime_rounded,
                  label: 'Nights stayed',
                  value: '${stay.nightsStayed ?? '—'}',
                ),
                _DetailRow(
                  icon: Icons.king_bed_rounded,
                  label: 'Rooms occupied',
                  value: '${stay.roomsOccupied ?? '—'}',
                ),
                if (stay.roomNumbers.isNotEmpty)
                  _DetailRow(
                    icon: Icons.meeting_room_rounded,
                    label: 'Room numbers',
                    value: stay.roomNumbers.join(', '),
                  ),
                if (stay.notes.isNotEmpty)
                  _DetailRow(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Notes',
                    value: stay.notes,
                  ),
                _DetailRow(
                  icon: Icons.place_rounded,
                  label: 'Municipality',
                  value: stay.municipality.isEmpty ? '—' : stay.municipality,
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          if (inHouse) ...[
            FilledButton.icon(
              onPressed: _busy ? null : _checkOut,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.logout_rounded, size: 20),
              label: const Text('Check out & review'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: buttonShape,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _goHome,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kInk,
                side: const BorderSide(color: _kBorder),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: buttonShape,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Done'),
            ),
          ] else
            FilledButton.icon(
              onPressed: _goHome,
              icon: const Icon(Icons.home_rounded, size: 20),
              label: const Text('Back to home'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: buttonShape,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${_months[d.month - 1]} ${d.day}, ${d.year} · $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Pops back to the tourist shell. `popUntil(isFirst)` is wrong here: a cold
  /// start at `/dashboard` keeps the `/` login route underneath it.
  void _goHome() {
    final nav = Navigator.of(context);
    var reachedShell = false;
    nav.popUntil((route) {
      if (route.settings.name == '/dashboard') {
        reachedShell = true;
        return true;
      }
      return route.isFirst;
    });
    if (!reachedShell) {
      nav.pushNamedAndRemoveUntil('/dashboard', (_) => false);
    }
  }

  void _openReview() {
    if (_busy) return;
    _showReview();
  }

  Future<void> _copyReference() async {
    await Clipboard.setData(ClipboardData(text: _stay.id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reference copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildHero(EstablishmentStayRequest stay, bool inHouse) {
    final checkedOut = stay.isCheckedOut;
    final colors = checkedOut
        ? const [Color(0xFF3B82F6), Color(0xFF1E40AF)]
        : const [Color(0xFF22C55E), Color(0xFF15803D)];
    final status = checkedOut
        ? 'Checked out'
        : inHouse
            ? 'Checked in'
            : 'Confirmed by front desk';
    final rooms = stay.roomNumbers.where((r) => r.trim().isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  checkedOut ? Icons.luggage_rounded : Icons.verified_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: colors.last,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      stay.establishmentName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    if (stay.municipality.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.place_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            stay.municipality,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _heroStat(
                Icons.bedtime_rounded,
                '${stay.nightsStayed ?? '—'}',
                stay.nightsStayed == 1 ? 'Night' : 'Nights',
              ),
              const SizedBox(width: 8),
              _heroStat(
                Icons.groups_rounded,
                '${stay.partySize}',
                stay.partySize == 1 ? 'Guest' : 'Guests',
              ),
              const SizedBox(width: 8),
              _heroStat(
                Icons.meeting_room_rounded,
                rooms.isEmpty ? '—' : rooms.join(', '),
                rooms.length > 1 ? 'Rooms' : 'Room',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _copyReference,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.confirmation_number_outlined,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Ref',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stay.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.copy_rounded,
                      size: 15,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewPrompt() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openReview,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.brandOrange,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brandOrange.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How was your stay?',
                      style: TextStyle(
                        color: _kInk,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Rate the hotel and your room — it takes 10 seconds.',
                      style: TextStyle(color: _kMuted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (var i = 0; i < 5; i++)
                          Icon(
                            Icons.star_outline_rounded,
                            size: 18,
                            color: AppTheme.brandOrange.withValues(alpha: 0.7),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _kMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _starsRow(IconData icon, String label, double rating) {
    final r = rating.round().clamp(0, 5);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.brandOrange),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: _kMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          for (var i = 1; i <= 5; i++)
            Icon(
              i <= r ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 20,
              color: i <= r ? const Color(0xFFF59E0B) : _kBorder,
            ),
          const SizedBox(width: 6),
          Text(
            '$r.0',
            style: const TextStyle(
              color: _kInk,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(EstablishmentStayReview review, bool lodging) {
    return _SectionCard(
      title: 'Your review',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _starsRow(Icons.apartment_rounded, 'Hotel', review.hotelRating),
          if (lodging)
            _starsRow(Icons.king_bed_rounded, 'Room', review.roomRating),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: _kPageBg,
                borderRadius: BorderRadius.circular(12),
                border: const Border(
                  left: BorderSide(color: Color(0xFFF97316), width: 3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.format_quote_rounded,
                    size: 20,
                    color: Color(0xFFF97316),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      review.comment,
                      style: const TextStyle(
                        color: _kInk,
                        fontSize: 13.5,
                        height: 1.45,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
