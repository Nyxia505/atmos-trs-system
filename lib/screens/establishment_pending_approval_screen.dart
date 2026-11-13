import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/navigation/role_router.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';

/// Shown after email/OTP verification while OPTACA has not approved the AE.
class EstablishmentPendingApprovalScreen extends StatefulWidget {
  const EstablishmentPendingApprovalScreen({super.key});

  @override
  State<EstablishmentPendingApprovalScreen> createState() =>
      _EstablishmentPendingApprovalScreenState();
}

class _EstablishmentPendingApprovalScreenState
    extends State<EstablishmentPendingApprovalScreen> {
  static const _primary = Color(0xFFF97316);
  static const _darkOrange = Color(0xFFEA580C);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _bg = Color(0xFFF8FAFC);
  static const _border = Color(0xFFE5E7EB);
  static const _dark = Color(0xFF1F2937);
  static const _muted = Color(0xFF64748B);
  static const _maxContent = 980.0;

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String? _toast;
  String _businessName = '';
  String _email = '';
  String _municipality = '';
  String _status = EstablishmentRegistryStatus.pending;
  String _permitNo = '';
  String _permitUrl = '';
  String _reviewNotes = '';
  DateTime? _submittedAt;
  bool _emailVerified = false;
  bool _registrationSaved = false;
  String _prevStatus = '';

  @override
  void initState() {
    super.initState();
    _load(showFullLoader: true);
  }

  Future<void> _load({bool showFullLoader = false}) async {
    if (showFullLoader) {
      setState(() {
        _loading = true;
        _error = null;
        _toast = null;
      });
    } else {
      setState(() {
        _error = null;
        _toast = null;
      });
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? AuthConfig.currentUserUid ?? '';
      if (uid.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Sign in again to view your registration status.';
        });
        return;
      }

      try {
        await user?.reload();
      } catch (_) {}

      final estSnap = await FirebaseFirestore.instance
          .collection(EstablishmentRegistrationService.establishmentsCollection)
          .doc(uid)
          .get();
      final userSnap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final est = estSnap.data() ?? const <String, dynamic>{};
      final userDoc = userSnap.data() ?? const <String, dynamic>{};

      DateTime? submitted;
      final created = est['createdAt'] ?? userDoc['createdAt'];
      if (created is Timestamp) submitted = created.toDate();

      // Establishment name only — never fall back to owner fullName.
      final estName = (est['businessName'] ?? est['name'] ?? '').toString().trim();
      final userBiz = (userDoc['businessName'] ?? '').toString().trim();
      final resolvedName = estName.isNotEmpty
          ? estName
          : (userBiz.isNotEmpty ? userBiz : 'Your establishment');

      final verifiedFlag = userDoc['isVerified'] == true ||
          (FirebaseAuth.instance.currentUser?.emailVerified ?? false);

      final nextStatus = EstablishmentRegistryStatus.normalize(
        (userDoc['status'] ?? est['status'] ?? 'pending').toString(),
      );

      if (!mounted) return;
      final statusUnchanged =
          _prevStatus.isNotEmpty && _prevStatus == nextStatus && !showFullLoader;

      setState(() {
        _businessName = resolvedName;
        _email = (userDoc['email'] ??
                est['email'] ??
                FirebaseAuth.instance.currentUser?.email ??
                '')
            .toString();
        _municipality =
            (est['municipality'] ?? userDoc['municipality'] ?? '').toString();
        _status = nextStatus;
        _permitNo = (est['businessPermitNo'] ?? userDoc['businessPermitNo'] ?? '')
            .toString();
        _permitUrl =
            (est['businessPermitUrl'] ?? userDoc['businessPermitUrl'] ?? '')
                .toString();
        _reviewNotes =
            (userDoc['reviewNotes'] ?? est['reviewNotes'] ?? '').toString();
        _submittedAt = submitted;
        _emailVerified = verifiedFlag;
        _registrationSaved = estSnap.exists || userSnap.exists;
        _loading = false;
        _prevStatus = nextStatus;
        if (statusUnchanged) {
          _toast = 'Status is still $_statusLabel. OPTACA has not updated yet.';
        }
      });

      if (EstablishmentRegistryStatus.isActive(nextStatus) && verifiedFlag) {
        final profile = await UserDirectoryService.getProfileByUid(
          uid,
          preferServer: true,
        );
        if (!mounted) return;
        if (profile != null && profile.isTourismEstablishment) {
          final route = RoleRouter.routeForEstablishment(profile);
          if (route == '/establishment-dashboard') {
            Navigator.of(context).pushReplacementNamed(route);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load registration status. Please try again.';
      });
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _load(showFullLoader: false);
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _backToLogin() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    AuthConfig.currentUserUid = null;
    await SessionStorage.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (_) => false);
  }

  Future<void> _viewPermit() async {
    final raw = _permitUrl.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      _snack('Could not open the Business Permit.');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack('Could not open the Business Permit.');
    } catch (_) {
      if (mounted) _snack('Could not open the Business Permit.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String get _statusLabel {
    switch (_status) {
      case EstablishmentRegistryStatus.active:
        return 'Approved';
      case EstablishmentRegistryStatus.rejected:
        return 'Rejected';
      case EstablishmentRegistryStatus.needsRevision:
        return 'Needs Revision';
      default:
        return 'Pending Review';
    }
  }

  Color get _statusColor {
    switch (_status) {
      case EstablishmentRegistryStatus.active:
        return const Color(0xFF16A34A);
      case EstablishmentRegistryStatus.rejected:
        return const Color(0xFFDC2626);
      case EstablishmentRegistryStatus.needsRevision:
        return _darkOrange;
      default:
        return _primary;
    }
  }

  String get _headline {
    switch (_status) {
      case EstablishmentRegistryStatus.rejected:
        return 'Registration Rejected';
      case EstablishmentRegistryStatus.needsRevision:
        return 'Additional Information Required';
      case EstablishmentRegistryStatus.active:
        return 'Registration Approved';
      default:
        return 'Registration Under Review';
    }
  }

  String get _description {
    switch (_status) {
      case EstablishmentRegistryStatus.rejected:
        return 'OPTACA reviewed your registration and did not approve it. See the reason below for next steps.';
      case EstablishmentRegistryStatus.needsRevision:
        return 'OPTACA requested corrections. Review the notes below, update the required information, then wait for another review.';
      case EstablishmentRegistryStatus.active:
        return 'Your establishment has been approved. You can access your Establishment Dashboard.';
      default:
        return 'Your email has been verified successfully. Your establishment registration has been submitted to OPTACA for review. Please wait for approval before accessing your Establishment Dashboard.';
    }
  }

  /// 0 submitted, 1 email, 2 optaca, 3 approved — index of current active step.
  int get _currentStepIndex {
    if (EstablishmentRegistryStatus.isActive(_status)) return 3;
    if (!_registrationSaved) return 0;
    if (!_emailVerified) return 1;
    return 2; // OPTACA review in progress (pending / rejected / needs_revision)
  }

  bool _stepCompleted(int index) {
    final current = _currentStepIndex;
    if (index < current) return true;
    if (index == 3) {
      return EstablishmentRegistryStatus.isActive(_status);
    }
    if (index == 2) {
      // Review "completed" only when a final decision of approved — otherwise active.
      return EstablishmentRegistryStatus.isActive(_status);
    }
    if (index == 1) return _emailVerified;
    if (index == 0) return _registrationSaved;
    return false;
  }

  bool _stepActive(int index) =>
      index == _currentStepIndex &&
      !EstablishmentRegistryStatus.isActive(_status);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 720;
    final horizontal = isWide ? 28.0 : 18.0;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _primary),
              )
            : RefreshIndicator(
                color: _primary,
                onRefresh: _refresh,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _maxContent),
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            isWide ? 36 : 24,
                            horizontal,
                            isWide ? 40 : 24,
                          ),
                          children: [
                            _buildHeader(isWide),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: const Color(0xFFDC2626),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                            if (_toast != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _toast!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: _muted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            SizedBox(height: isWide ? 28 : 22),
                            _buildProgress(isWide),
                            SizedBox(height: isWide ? 24 : 18),
                            _buildInfoCard(isWide),
                            SizedBox(height: isWide ? 16 : 14),
                            _buildApprovalBanner(),
                            if (_reviewNotes.trim().isNotEmpty &&
                                (_status ==
                                        EstablishmentRegistryStatus.rejected ||
                                    _status ==
                                        EstablishmentRegistryStatus
                                            .needsRevision)) ...[
                              const SizedBox(height: 14),
                              _buildDecisionNotes(),
                            ],
                            SizedBox(height: isWide ? 24 : 18),
                            _buildActions(isWide),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(bool isWide) {
    return Column(
      children: [
        SizedBox(
          width: isWide ? 88 : 76,
          height: isWide ? 88 : 76,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _lightOrange,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
              ),
              Icon(
                _status == EstablishmentRegistryStatus.rejected
                    ? Icons.storefront_outlined
                    : Icons.storefront_rounded,
                color: _statusColor,
                size: isWide ? 36 : 32,
              ),
              Positioned(
                right: 6,
                bottom: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFFED7AA)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Icon(
                    _status == EstablishmentRegistryStatus.rejected
                        ? Icons.cancel_rounded
                        : _status == EstablishmentRegistryStatus.needsRevision
                            ? Icons.edit_note_rounded
                            : Icons.hourglass_top_rounded,
                    size: 14,
                    color: _statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: isWide ? 20 : 16),
        Text(
          _headline,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: isWide ? 28 : 22,
            fontWeight: FontWeight.w800,
            color: _dark,
            letterSpacing: -0.4,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            _description,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: isWide ? 14.5 : 13.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: _muted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(bool isWide) {
    final steps = <({String label, IconData icon})>[
      (label: 'Registration Submitted', icon: Icons.assignment_turned_in_outlined),
      (label: 'Email Verified', icon: Icons.mark_email_read_outlined),
      (label: 'OPTACA Review', icon: Icons.policy_outlined),
      (label: 'Account Approved', icon: Icons.verified_outlined),
    ];

    if (isWide) {
      return Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: Container(
                      height: 2,
                      color: _stepCompleted(i) || _stepActive(i)
                          ? _primary.withValues(alpha: 0.55)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              _ProgressStep(
                label: steps[i].label,
                icon: steps[i].icon,
                completed: _stepCompleted(i),
                active: _stepActive(i),
                compact: false,
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _ProgressDot(
                      icon: steps[i].icon,
                      completed: _stepCompleted(i),
                      active: _stepActive(i),
                    ),
                    if (i < steps.length - 1)
                      Container(
                        width: 2,
                        height: 18,
                        color: _stepCompleted(i + 1) || _stepActive(i + 1)
                            ? _primary.withValues(alpha: 0.5)
                            : const Color(0xFFE2E8F0),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 10),
                    child: Text(
                      steps[i].label,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: _stepActive(i) || _stepCompleted(i)
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _stepActive(i)
                            ? _primary
                            : _stepCompleted(i)
                                ? _dark
                                : _muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool isWide) {
    final permitUploaded = _permitUrl.trim().isNotEmpty;
    final submittedLabel = _submittedAt == null
        ? '—'
        : MaterialLocalizations.of(context).formatFullDate(_submittedAt!);

    final rows = <({IconData icon, String label, String value, Widget? trailing})>[
      (
        icon: Icons.store_mall_directory_outlined,
        label: 'Establishment Name',
        value: _businessName,
        trailing: null,
      ),
      (
        icon: Icons.mail_outline_rounded,
        label: 'Registered Email',
        value: _email.isEmpty ? '—' : _email,
        trailing: null,
      ),
      (
        icon: Icons.location_city_outlined,
        label: 'Municipality / City',
        value: _municipality.isEmpty ? '—' : _municipality,
        trailing: null,
      ),
      (
        icon: Icons.badge_outlined,
        label: 'Business Permit Number',
        value: _permitNo.trim().isEmpty ? '—' : _permitNo.trim(),
        trailing: null,
      ),
      (
        icon: Icons.upload_file_outlined,
        label: 'Business Permit',
        value: permitUploaded ? 'Uploaded' : 'Missing',
        trailing: permitUploaded
            ? TextButton(
                onPressed: _viewPermit,
                style: TextButton.styleFrom(
                  foregroundColor: _primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'View Permit',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              )
            : null,
      ),
      (
        icon: Icons.event_outlined,
        label: 'Submission Date',
        value: submittedLabel,
        trailing: null,
      ),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(
        isWide ? 20 : 16,
        isWide ? 18 : 14,
        isWide ? 20 : 16,
        isWide ? 10 : 8,
      ),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Establishment Information',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
          const SizedBox(height: 12),
          if (isWide)
            ..._chunkPairs(rows).map((pair) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _infoTile(pair.$1)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: pair.$2 != null
                          ? _infoTile(pair.$2!)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              );
            })
          else
            for (final r in rows) _infoTile(r),
        ],
      ),
    );
  }

  List<(
    ({IconData icon, String label, String value, Widget? trailing}),
    ({IconData icon, String label, String value, Widget? trailing})?
  )> _chunkPairs(
    List<({IconData icon, String label, String value, Widget? trailing})> rows,
  ) {
    final out = <(
      ({IconData icon, String label, String value, Widget? trailing}),
      ({IconData icon, String label, String value, Widget? trailing})?
    )>[];
    for (var i = 0; i < rows.length; i += 2) {
      out.add((
        rows[i],
        i + 1 < rows.length ? rows[i + 1] : null,
      ));
    }
    return out;
  }

  Widget _infoTile(
    ({IconData icon, String label, String value, Widget? trailing}) row,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _lightOrange,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(row.icon, size: 16, color: _primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.value,
                  softWrap: true,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _dark,
                    height: 1.35,
                  ),
                ),
                if (row.trailing != null) ...[
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: row.trailing!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalBanner() {
    final isRejected = _status == EstablishmentRegistryStatus.rejected;
    final isRevision = _status == EstablishmentRegistryStatus.needsRevision;
    final bg = isRejected
        ? const Color(0xFFFEF2F2)
        : isRevision
            ? const Color(0xFFFFF7ED)
            : _lightOrange;
    final border = isRejected
        ? const Color(0xFFFECACA)
        : const Color(0xFFFED7AA);
    final support = isRejected
        ? 'Your registration was not approved. Contact OPTACA if you need clarification.'
        : isRevision
            ? 'Please prepare the requested corrections. You will keep the same account — do not register again.'
            : 'Your registration is currently being reviewed by OPTACA. You will be notified once a decision has been made.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isRejected
                ? Icons.cancel_outlined
                : isRevision
                    ? Icons.edit_note_rounded
                    : Icons.hourglass_top_rounded,
            color: _statusColor,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Approval Status',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _dark,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _statusColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _statusLabel,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  support,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecisionNotes() {
    final isRejected = _status == EstablishmentRegistryStatus.rejected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRejected ? const Color(0xFFFECACA) : const Color(0xFFFED7AA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isRejected ? 'Rejection reason' : 'Requested corrections',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _reviewNotes.trim(),
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: _dark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(bool isWide) {
    final refreshBtn = FilledButton.icon(
      onPressed: _refreshing ? null : _refresh,
      icon: _refreshing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.refresh_rounded, size: 18),
      label: Text(_refreshing ? 'Checking…' : 'Refresh Status'),
      style: FilledButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _primary.withValues(alpha: 0.7),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final loginBtn = OutlinedButton.icon(
      onPressed: _backToLogin,
      icon: const Icon(Icons.login_rounded, size: 18),
      label: const Text('Back to Login'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _primary,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFFDBA74)),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    if (isWide) {
      return Row(
        children: [
          Expanded(child: refreshBtn),
          const SizedBox(width: 12),
          Expanded(child: loginBtn),
        ],
      );
    }

    return Column(
      children: [
        refreshBtn,
        const SizedBox(height: 10),
        loginBtn,
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({
    required this.label,
    required this.icon,
    required this.completed,
    required this.active,
    required this.compact,
  });

  final String label;
  final IconData icon;
  final bool completed;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 72 : 110,
      child: Column(
        children: [
          _ProgressDot(icon: icon, completed: completed, active: active),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              height: 1.25,
              fontWeight: active || completed ? FontWeight.w700 : FontWeight.w500,
              color: active
                  ? const Color(0xFFF97316)
                  : completed
                      ? const Color(0xFF1F2937)
                      : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressDot extends StatelessWidget {
  const _ProgressDot({
    required this.icon,
    required this.completed,
    required this.active,
  });

  final IconData icon;
  final bool completed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFFF97316);
    final bg = completed || active ? primary : const Color(0xFFF1F5F9);
    final fg = completed || active ? Colors.white : const Color(0xFF94A3B8);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: active
            ? [
                BoxShadow(
                  color: primary.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Icon(
        completed ? Icons.check_rounded : icon,
        size: 18,
        color: fg,
      ),
    );
  }
}
