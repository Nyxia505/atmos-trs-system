import 'package:flutter/material.dart';

import '../services/optaca_account_admin_service.dart';
import '../theme/tourism_app_theme.dart';
import 'optaca_portal_ui.dart';

/// Canonical LGU ids used by `optacaManageAccount` / Firestore profiles.
const List<({String id, String name})> kOptacaMunicipalityOptions = [
  (id: 'oroquieta', name: 'Oroquieta City'),
  (id: 'ozamiz', name: 'Ozamis City'),
  (id: 'tangub', name: 'Tangub City'),
  (id: 'aloran', name: 'Aloran'),
  (id: 'baliangao', name: 'Baliangao'),
  (id: 'bonifacio', name: 'Bonifacio'),
  (id: 'calamba', name: 'Calamba'),
  (id: 'clarin', name: 'Clarin'),
  (id: 'concepcion', name: 'Concepcion'),
  (id: 'dvc', name: 'Don Victoriano Chiongbian'),
  (id: 'jimenez', name: 'Jimenez'),
  (id: 'lopezjaena', name: 'Lopez Jaena'),
  (id: 'panaon', name: 'Panaon'),
  (id: 'plaridel', name: 'Plaridel'),
  (id: 'sapangdalaga', name: 'Sapang Dalaga'),
  (id: 'sinacaban', name: 'Sinacaban'),
  (id: 'tudela', name: 'Tudela'),
];

String _normalizeLguMunicipalityId(String raw) {
  final id = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), '');
  if (id == 'ozamis') return 'ozamiz';
  if (id == 'donvictoriano' ||
      id == 'donvictorianochiongbian' ||
      id == 'dvcchiongbian') {
    return 'dvc';
  }
  return id;
}

String? _inferLguMunicipalityId({
  String municipalityId = '',
  String municipality = '',
  String email = '',
}) {
  final fromId = _normalizeLguMunicipalityId(municipalityId);
  if (fromId.isNotEmpty &&
      kOptacaMunicipalityOptions.any((m) => m.id == fromId)) {
    return fromId;
  }

  final fromName = _normalizeLguMunicipalityId(municipality);
  if (fromName.isNotEmpty) {
    for (final m in kOptacaMunicipalityOptions) {
      if (_normalizeLguMunicipalityId(m.id) == fromName ||
          _normalizeLguMunicipalityId(m.name) == fromName ||
          municipality.toLowerCase().contains(m.name.toLowerCase()) ||
          m.name.toLowerCase().contains(municipality.toLowerCase())) {
        return m.id;
      }
    }
  }

  final mail = email.trim().toLowerCase();
  final tourismDot = RegExp(r'^tourism\.([a-z0-9]+)@').firstMatch(mail);
  if (tourismDot != null) {
    final id = _normalizeLguMunicipalityId(tourismDot.group(1)!);
    if (kOptacaMunicipalityOptions.any((m) => m.id == id)) return id;
  }
  final tourismPrefix = RegExp(r'^tourism([a-z0-9]+)@').firstMatch(mail);
  if (tourismPrefix != null) {
    final id = _normalizeLguMunicipalityId(tourismPrefix.group(1)!);
    if (kOptacaMunicipalityOptions.any((m) => m.id == id)) return id;
  }
  return null;
}

String _lguMunicipalityName(String id) {
  for (final m in kOptacaMunicipalityOptions) {
    if (m.id == id) return m.name;
  }
  return id;
}

bool _isMissingLguAccount(Map<String, dynamic> account) =>
    account['isPlaceholder'] == true ||
    (account['status']?.toString().toLowerCase() == 'missing');

/// One row per Misamis Occidental LGU. Existing Auth/Firestore accounts are
/// attached; municipalities without an account get a placeholder row.
List<Map<String, dynamic>> _buildAllLguAccountRows(
  List<Map<String, dynamic>> existing,
) {
  final byMuni = <String, List<Map<String, dynamic>>>{};
  final orphans = <Map<String, dynamic>>[];

  for (final raw in existing) {
    final inferred = _inferLguMunicipalityId(
      municipalityId: (raw['municipalityId'] ?? '').toString(),
      municipality: (raw['municipality'] ?? '').toString(),
      email: (raw['email'] ?? '').toString(),
    );
    final enriched = <String, dynamic>{
      ...raw,
      if (inferred != null) ...{
        'municipalityId': inferred,
        'municipality': _lguMunicipalityName(inferred),
      },
      'isPlaceholder': false,
    };
    if (inferred == null) {
      orphans.add(enriched);
    } else {
      byMuni.putIfAbsent(inferred, () => []).add(enriched);
    }
  }

  Map<String, dynamic> pickPrimary(List<Map<String, dynamic>> rows) {
    rows.sort((a, b) {
      final aActive = _isActiveStatus(a) ? 0 : 1;
      final bActive = _isActiveStatus(b) ? 0 : 1;
      if (aActive != bActive) return aActive - bActive;
      final aMs = (a['createdAtMs'] as num?)?.toInt() ?? 0;
      final bMs = (b['createdAtMs'] as num?)?.toInt() ?? 0;
      return bMs.compareTo(aMs);
    });
    return rows.first;
  }

  final rows = <Map<String, dynamic>>[];
  for (final m in kOptacaMunicipalityOptions) {
    final matches = byMuni[m.id];
    if (matches == null || matches.isEmpty) {
      rows.add({
        'uid': '',
        'isPlaceholder': true,
        'municipalityId': m.id,
        'municipality': m.name,
        'fullName': 'No account yet',
        'email': '',
        'role': 'tourism',
        'status': 'missing',
        'createdAtMs': 0,
        'reviewFlags': <String>[],
      });
      continue;
    }
    final primary = pickPrimary(matches);
    rows.add(primary);
    // Extra accounts for the same LGU (rare) still appear under that city.
    for (var i = 0; i < matches.length; i++) {
      if (identical(matches[i], primary) || matches[i]['uid'] == primary['uid']) {
        continue;
      }
      rows.add(matches[i]);
    }
  }
  rows.addAll(orphans);
  return rows;
}

Widget _lguAccountStatusBadge(Map<String, dynamic> account) {
  if (_isMissingLguAccount(account)) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF64748B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'No account',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }
  return _statusBadge(_isActiveStatus(account));
}

/// OPTACA LGU & User Account Management (three tabs).
class OptacaAccountsPanel extends StatefulWidget {
  const OptacaAccountsPanel({super.key});

  @override
  State<OptacaAccountsPanel> createState() => _OptacaAccountsPanelState();
}

class _OptacaAccountsPanelState extends State<OptacaAccountsPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final padH = wide ? 20.0 : 12.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padH, 16, padH, 0),
          child: const OptacaSectionHeader(
            title: 'LGU Account Management',
            caption:
                'Manage LGU administrators, registered users, and account security.',
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padH),
          child: Container(
            decoration: BoxDecoration(
              color: OptacaAdminTheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OptacaAdminTheme.border),
            ),
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: OptacaAdminTheme.primary,
              unselectedLabelColor: OptacaAdminTheme.textMuted,
              indicatorColor: OptacaAdminTheme.primary,
              indicatorWeight: 3,
              labelPadding: const EdgeInsets.symmetric(horizontal: 18),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
              tabs: const [
                Tab(text: 'LGU Accounts'),
                Tab(text: 'User Accounts'),
                Tab(text: 'Activity Logs'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _LguAccountsTab(),
              _UserAccountsTab(),
              _ActivityLogsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Shared helpers ──────────────────────────────────────────────────────────

bool _isActiveStatus(Map<String, dynamic> account) {
  final status = (account['status'] ?? 'active').toString().toLowerCase();
  return status != 'inactive' &&
      status != 'disabled' &&
      status != 'deactivated';
}

String _formatDate(dynamic ms) {
  final value = ms is num ? ms.toInt() : 0;
  if (value <= 0) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}

String _adminLabel(Map<String, dynamic> log) {
  final name = (log['actorName'] ?? '—').toString();
  final uid = (log['actorUid'] ?? '').toString();
  if (uid.isEmpty) return name;
  return '$name\n$uid';
}

Future<void> _showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFDC2626) : null,
      behavior: SnackBarBehavior.floating,
    ),
  );
  return Future.value();
}

Widget _statusBadge(bool active) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: active
          ? OptacaAdminTheme.success.withValues(alpha: 0.12)
          : const Color(0xFFDC2626).withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      active ? 'Active' : 'Deactivated',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: active ? OptacaAdminTheme.success : const Color(0xFFDC2626),
      ),
    ),
  );
}

Widget _summaryCard({
  required String label,
  required String value,
  required IconData icon,
  required Color accent,
  double? width,
}) {
  return SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: OptacaPortalUi.card(),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: OptacaAdminTheme.text,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: OptacaAdminTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

double _summaryCardWidth(double maxWidth) {
  if (maxWidth >= 980) return (maxWidth - 36) / 4;
  if (maxWidth >= 640) return (maxWidth - 12) / 2;
  return maxWidth;
}

double _toolbarFieldWidth(double maxWidth, double preferred) {
  if (maxWidth <= 0) return preferred;
  return preferred > maxWidth ? maxWidth : preferred;
}

const double _kCompactBreakpoint = 900;

bool _isCompactWidth(double width) => width < _kCompactBreakpoint;

EdgeInsets _tabListPadding(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 1100;
  final h = wide ? 20.0 : 12.0;
  return EdgeInsets.fromLTRB(h, 12, h, 28);
}

Widget _paginationBar({
  required int page,
  required bool hasMore,
  required bool busy,
  required VoidCallback? onPrev,
  required VoidCallback? onNext,
}) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    alignment: WrapAlignment.spaceBetween,
    children: [
      Text(
        'Page ${page + 1}',
        style: const TextStyle(color: OptacaAdminTheme.textMuted),
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: onPrev,
            child: const Text('Previous'),
          ),
          TextButton(
            onPressed: onNext,
            child: const Text('Next'),
          ),
        ],
      ),
    ],
  );
}

Widget _tableHeaderCell(String label, {int flex = 1}) {
  return Expanded(
    flex: flex,
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: OptacaAdminTheme.text,
      ),
    ),
  );
}

Widget _tableBodyCell(
  Widget child, {
  int flex = 1,
}) {
  return Expanded(flex: flex, child: child);
}

Widget _ellipsize(
  String text, {
  TextStyle? style,
  int maxLines = 1,
}) {
  return Text(
    text,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    softWrap: maxLines > 1,
    style: style ??
        const TextStyle(
          fontSize: 13.5,
          color: OptacaAdminTheme.text,
        ),
  );
}

Widget _responsiveAccountTable({
  required List<String> headers,
  required List<int> flexes,
  required List<Widget> Function(Map<String, dynamic> row) buildCells,
  required List<Map<String, dynamic>> rows,
}) {
  assert(headers.length == flexes.length);
  return Container(
    width: double.infinity,
    decoration: OptacaPortalUi.card(),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: OptacaAdminTheme.lightOrange.withValues(alpha: 0.45),
          child: Row(
            children: [
              for (var i = 0; i < headers.length; i++)
                _tableHeaderCell(headers[i], flex: flexes[i]),
            ],
          ),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            const Divider(height: 1, color: OptacaAdminTheme.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var c = 0; c < flexes.length; c++)
                  _tableBodyCell(
                    buildCells(rows[i])[c],
                    flex: flexes[c],
                  ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _accountInfoCard({
  required String title,
  required List<(String, String)> details,
  required Widget trailing,
  Widget? badge,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: OptacaPortalUi.card(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: OptacaAdminTheme.text,
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              badge,
            ],
          ],
        ),
        const SizedBox(height: 10),
        for (final detail in details) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 108,
                  child: Text(
                    detail.$1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: OptacaAdminTheme.textMuted,
                    ),
                  ),
                ),
                Expanded(child: _ellipsize(detail.$2, maxLines: 2)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: trailing),
      ],
    ),
  );
}

// ─── LGU Accounts ────────────────────────────────────────────────────────────

class _LguAccountsTab extends StatefulWidget {
  const _LguAccountsTab();

  @override
  State<_LguAccountsTab> createState() => _LguAccountsTabState();
}

class _LguAccountsTabState extends State<_LguAccountsTab> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _allRows = const [];
  List<Map<String, dynamic>> _accounts = const [];
  Map<String, dynamic> _summary = const {};
  String _status = 'All';
  String _municipalityId = 'All';
  int _page = 0;
  bool _hasMore = false;
  bool _busy = false;
  static const int _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _applyFilters({int page = 0}) {
    final q = _search.text.trim().toLowerCase();
    final statusFilter = _status.toLowerCase();
    final muni = _municipalityId;

    var filtered = _allRows.where((row) {
      if (muni != 'All') {
        final id = (row['municipalityId'] ?? '').toString().toLowerCase();
        if (id != muni) return false;
      }
      if (statusFilter == 'active') {
        if (_isMissingLguAccount(row) || !_isActiveStatus(row)) return false;
      } else if (statusFilter == 'deactivated') {
        if (_isMissingLguAccount(row) || _isActiveStatus(row)) return false;
      } else if (statusFilter == 'missing' || statusFilter == 'no account') {
        if (!_isMissingLguAccount(row)) return false;
      }
      if (q.isNotEmpty) {
        final hay = [
          row['fullName'],
          row['email'],
          row['municipality'],
          row['municipalityId'],
          row['uid'],
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    final realAccounts =
        _allRows.where((r) => !_isMissingLguAccount(r)).toList();
    final covered = <String>{};
    for (final row in realAccounts) {
      final id = (row['municipalityId'] ?? '').toString();
      if (id.isNotEmpty) covered.add(id);
    }

    final start = page * _pageSize;
    final pageRows = filtered.skip(start).take(_pageSize).toList();
    _accounts = pageRows;
    _page = page;
    _hasMore = start + _pageSize < filtered.length;
    _summary = {
      'total': realAccounts.length,
      'active': realAccounts.where(_isActiveStatus).length,
      'deactivated':
          realAccounts.where((r) => !_isActiveStatus(r)).length,
      'municipalitiesCovered': covered.length,
      'municipalitiesTotal': kOptacaMunicipalityOptions.length,
      'missing': kOptacaMunicipalityOptions.length - covered.length,
      'needsReview': 0,
      'visible': filtered.length,
    };
  }

  Future<void> _load({int page = 0}) async {
    setState(() {
      _loading = true;
      _error = null;
      _page = page;
    });
    try {
      // Pull every LGU Auth/Firestore account, then fill missing municipalities
      // so OPTACA always sees all 17 LGUs.
      final result = await OptacaAccountAdminService.listAccounts(
        accountType: 'lgu',
        search: '',
        status: '',
        municipalityId: '',
        page: 0,
        pageSize: 500,
      );
      if (!mounted) return;
      setState(() {
        _allRows = _buildAllLguAccountRows(result.accounts);
        _applyFilters(page: page);
        _loading = false;
      });
    } on OptacaAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load LGU accounts.';
      });
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (success != null) await _showSnack(context, success);
      await _load(page: _page);
    } on OptacaAccountException catch (e) {
      if (!mounted) return;
      await _showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create({String? municipalityId}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LguAccountFormDialog(
        initialMunicipalityId: municipalityId,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _edit(Map<String, dynamic> account) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LguAccountFormDialog(existing: account),
    );
    if (saved == true) await _load(page: _page);
  }

  Future<void> _directResetPassword(Map<String, dynamic> account) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdminDirectResetPasswordDialog(account: account),
    );
    if (ok == true && mounted) {
      await _showSnack(context, 'Password successfully reset.');
      await _load(page: _page);
    }
  }

  Future<void> _sendPasswordResetEmail(Map<String, dynamic> account) async {
    await _run(
      () => OptacaAccountAdminService.call({
        'action': 'sendPasswordReset',
        'uid': account['uid'],
      }),
      success: 'Password reset email sent.',
    );
  }

  Future<void> _toggle(Map<String, dynamic> account) async {
    final active = _isActiveStatus(account);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(active ? 'Deactivate account' : 'Reactivate account'),
        content: Text(
          active
              ? 'Deactivate ${account['fullName'] ?? account['email']} '
                  '(${account['municipality'] ?? 'LGU'})?\n\n'
                  'They will not be able to sign in. Existing data is preserved.'
              : 'Reactivate ${account['fullName'] ?? account['email']}?\n\n'
                  'They can sign in again with their existing credentials.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(active ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => OptacaAccountAdminService.call({
        'action': 'setStatus',
        'uid': account['uid'],
        'active': !active,
      }),
      success: active ? 'Account deactivated.' : 'Account reactivated.',
    );
  }

  Future<void> _view(Map<String, dynamic> account) async {
    final flags = (account['reviewFlags'] is List)
        ? (account['reviewFlags'] as List).map((e) => e.toString()).toList()
        : <String>[];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text((account['fullName'] ?? 'LGU account').toString()),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 420.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detail('Email', account['email']),
              _detail('Municipality', account['municipality']),
              _detail('Role', 'LGU Admin'),
              _detail('Status', _isActiveStatus(account) ? 'Active' : 'Deactivated'),
              _detail('UID', account['uid']),
              _detail('Created', _formatDate(account['createdAtMs'])),
              if (flags.isNotEmpty)
                _detail('Needs review', flags.join(', ')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (flags.isNotEmpty)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _edit(account);
              },
              child: const Text('Repair profile'),
            ),
        ],
      ),
    );
  }

  Widget _detail(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: OptacaAdminTheme.textMuted,
            ),
          ),
          SelectableText(
            (value ?? '—').toString(),
            style: const TextStyle(fontSize: 14.5, color: OptacaAdminTheme.text),
          ),
        ],
      ),
    );
  }

  Future<void> _reconcile() async {
    await _run(() async {
      final issues = await OptacaAccountAdminService.reconcileLguAccounts();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Account reconciliation'),
          content: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 480.0),
            child: issues.isEmpty
                ? const Text('No incomplete LGU accounts found.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final issue in issues)
                        ListTile(
                          dense: true,
                          title: Text(
                            (issue['fullName'] ?? issue['email'] ?? issue['uid'])
                                .toString(),
                          ),
                          subtitle: Text(
                            ((issue['reviewFlags'] as List?) ?? const [])
                                .join(', '),
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    });
  }

  Widget _actionsMenu(Map<String, dynamic> account) {
    if (_isMissingLguAccount(account)) {
      return IconButton(
        tooltip: 'Create LGU account',
        onPressed: _busy
            ? null
            : () => _create(
                  municipalityId: (account['municipalityId'] ?? '').toString(),
                ),
        icon: const Icon(Icons.person_add_alt_1_rounded),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      enabled: !_busy,
      onSelected: (value) {
        switch (value) {
          case 'view':
            _view(account);
          case 'edit':
            _edit(account);
          case 'password':
            _directResetPassword(account);
          case 'email_reset':
            _sendPasswordResetEmail(account);
          case 'toggle':
            _toggle(account);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'view', child: Text('View')),
        const PopupMenuItem(value: 'edit', child: Text('Edit Account')),
        const PopupMenuItem(value: 'password', child: Text('Reset Password')),
        const PopupMenuItem(
          value: 'email_reset',
          child: Text('Send reset email'),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Text(
            _isActiveStatus(account)
                ? 'Deactivate Account'
                : 'Reactivate Account',
          ),
        ),
      ],
      child: const Icon(Icons.more_vert_rounded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final municipalities = kOptacaMunicipalityOptions;
    return ListView(
      padding: _tabListPadding(context),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cardW = _summaryCardWidth(constraints.maxWidth);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _summaryCard(
                  width: cardW,
                  label: 'Total LGU Accounts',
                  value: OptacaAdminTheme.formatCount(
                    (_summary['total'] as num?)?.toInt() ?? 0,
                  ),
                  icon: Icons.groups_rounded,
                  accent: OptacaAdminTheme.primary,
                ),
                _summaryCard(
                  width: cardW,
                  label: 'Active Accounts',
                  value: OptacaAdminTheme.formatCount(
                    (_summary['active'] as num?)?.toInt() ?? 0,
                  ),
                  icon: Icons.verified_user_rounded,
                  accent: OptacaAdminTheme.success,
                ),
                _summaryCard(
                  width: cardW,
                  label: 'LGUs Covered',
                  value:
                      '${OptacaAdminTheme.formatCount((_summary['municipalitiesCovered'] as num?)?.toInt() ?? 0)}'
                      ' / '
                      '${OptacaAdminTheme.formatCount((_summary['municipalitiesTotal'] as num?)?.toInt() ?? kOptacaMunicipalityOptions.length)}',
                  icon: Icons.location_city_rounded,
                  accent: const Color(0xFF2563EB),
                ),
                _summaryCard(
                  width: cardW,
                  label: 'Missing Accounts',
                  value: OptacaAdminTheme.formatCount(
                    (_summary['missing'] as num?)?.toInt() ?? 0,
                  ),
                  icon: Icons.person_off_rounded,
                  accent: const Color(0xFF64748B),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: OptacaPortalUi.card(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final compact = _isCompactWidth(maxW);
              final searchW = compact ? maxW : _toolbarFieldWidth(maxW, 280);
              final filterW = compact
                  ? (maxW - 10) / 2
                  : _toolbarFieldWidth(maxW, 180);
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: searchW,
                    child: TextField(
                      controller: _search,
                      decoration: OptacaPortalUi.searchDecoration(
                        hint: 'Search name, email, or municipality',
                      ),
                      onSubmitted: (_) {
                        setState(() => _applyFilters());
                      },
                    ),
                  ),
                  SizedBox(
                    width: filterW,
                    child: DropdownButtonFormField<String>(
                      initialValue: _municipalityId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Municipality',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'All',
                          child: Text(
                            'All LGUs',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        for (final m in municipalities)
                          DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              m.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _municipalityId = v ?? 'All';
                          _applyFilters();
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: compact ? filterW : _toolbarFieldWidth(maxW, 150),
                    child: DropdownButtonFormField<String>(
                      initialValue: _status,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(value: 'Active', child: Text('Active')),
                        DropdownMenuItem(
                          value: 'Deactivated',
                          child: Text('Deactivated'),
                        ),
                        DropdownMenuItem(
                          value: 'Missing',
                          child: Text('No account'),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _status = v ?? 'All';
                          _applyFilters();
                        });
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _busy ? null : () => _load(page: _page),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _reconcile,
                    icon: const Icon(Icons.rule_folder_outlined, size: 18),
                    label: Text(compact ? 'Reconcile' : 'Reconcile'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _create(),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: Text(compact ? 'Create' : 'Create LGU Account'),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Column(
            children: [
              OptacaEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load accounts',
                message: _error!,
              ),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          )
        else if (_accounts.isEmpty)
          const OptacaEmptyState(
            icon: Icons.manage_accounts_outlined,
            title: 'No matching LGUs',
            message:
                'All 17 Misamis Occidental LGUs are listed here. Adjust search or status filters to find one.',
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              if (_isCompactWidth(constraints.maxWidth)) {
                return Column(
                  children: [
                    for (final account in _accounts) ...[
                      _accountInfoCard(
                        title: (account['municipality'] ??
                                account['fullName'] ??
                                'LGU')
                            .toString(),
                        badge: _lguAccountStatusBadge(account),
                        details: [
                          (
                            'Municipality',
                            (account['municipality'] ??
                                    account['municipalityId'] ??
                                    '—')
                                .toString(),
                          ),
                          (
                            'Email',
                            _isMissingLguAccount(account)
                                ? 'Not created'
                                : (account['email'] ?? '—').toString(),
                          ),
                          (
                            'Name',
                            _isMissingLguAccount(account)
                                ? '—'
                                : (account['fullName'] ?? '—').toString(),
                          ),
                          (
                            'Created',
                            _isMissingLguAccount(account)
                                ? '—'
                                : _formatDate(account['createdAtMs']),
                          ),
                        ],
                        trailing: _actionsMenu(account),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              return _responsiveAccountTable(
                headers: const [
                  'LGU / Municipality',
                  'Full Name',
                  'Email Address',
                  'Role',
                  'Status',
                  'Date Created',
                  'Actions',
                ],
                flexes: const [2, 2, 3, 1, 1, 2, 1],
                rows: _accounts,
                buildCells: (account) => [
                  _ellipsize(
                    (account['municipality'] ??
                            account['municipalityId'] ??
                            '—')
                        .toString(),
                  ),
                  _ellipsize(
                    _isMissingLguAccount(account)
                        ? '—'
                        : (((account['reviewFlags'] is List) &&
                                (account['reviewFlags'] as List).isNotEmpty)
                            ? '⚑ ${(account['fullName'] ?? '—')}'
                            : (account['fullName'] ?? '—').toString()),
                  ),
                  _ellipsize(
                    _isMissingLguAccount(account)
                        ? 'Not created'
                        : (account['email'] ?? '—').toString(),
                  ),
                  _ellipsize(
                    _isMissingLguAccount(account) ? '—' : 'LGU Admin',
                  ),
                  _lguAccountStatusBadge(account),
                  _ellipsize(
                    _isMissingLguAccount(account)
                        ? '—'
                        : _formatDate(account['createdAtMs']),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _actionsMenu(account),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _paginationBar(
            page: _page,
            hasMore: _hasMore,
            busy: _busy,
            onPrev: _page == 0 || _busy
                ? null
                : () => setState(() => _applyFilters(page: _page - 1)),
            onNext: !_hasMore || _busy
                ? null
                : () => setState(() => _applyFilters(page: _page + 1)),
          ),
        ],
      ],
    );
  }
}

class _LguAccountFormDialog extends StatefulWidget {
  const _LguAccountFormDialog({
    this.existing,
    this.initialMunicipalityId,
  });

  final Map<String, dynamic>? existing;
  final String? initialMunicipalityId;

  @override
  State<_LguAccountFormDialog> createState() => _LguAccountFormDialogState();
}

class _LguAccountFormDialogState extends State<_LguAccountFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late final TextEditingController _confirm;
  late String _municipalityId;
  late String _role;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?['fullName']?.toString() ?? '');
    _email = TextEditingController(text: existing?['email']?.toString() ?? '');
    _password = TextEditingController();
    _confirm = TextEditingController();
    final prefillId = (existing?['municipalityId']?.toString().isNotEmpty == true)
        ? existing!['municipalityId'].toString()
        : (widget.initialMunicipalityId?.trim().isNotEmpty == true
            ? widget.initialMunicipalityId!.trim().toLowerCase()
            : kOptacaMunicipalityOptions.first.id);
    _municipalityId = prefillId == 'ozamis' ? 'ozamiz' : prefillId;
    _role = 'tourism';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim().toLowerCase();
    if (name.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Full name and a valid email are required.');
      return;
    }
    if (!_editing) {
      if (_password.text != _confirm.text) {
        setState(() => _error = 'Passwords do not match.');
        return;
      }
      if (_password.text.length < 8) {
        setState(() => _error = 'Password must be at least 8 characters.');
        return;
      }
    }

    if (_editing) {
      final municipalityChanged = _municipalityId !=
          (widget.existing?['municipalityId']?.toString() ?? '');
      if (municipalityChanged) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm municipality change'),
            content: const Text(
              'Changing the municipality reassigns this LGU account. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await OptacaAccountAdminService.call({
          'action': 'update',
          'uid': widget.existing!['uid'],
          'fullName': name,
          'email': email,
          'municipalityId': _municipalityId,
          'role': _role,
        });
      } else {
        await OptacaAccountAdminService.createStakeholderAccount(
          fullName: name,
          email: email,
          password: _password.text,
          municipalityId: _municipalityId,
          role: _role,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on OptacaAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit LGU Account' : 'Create LGU Account'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 460.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              TextField(
                controller: _email,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Email Address'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _municipalityId,
                decoration: const InputDecoration(labelText: 'Municipality / City'),
                items: [
                  for (final m in kOptacaMunicipalityOptions)
                    DropdownMenuItem(value: m.id, child: Text(m.name)),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _municipalityId = v ?? _municipalityId),
              ),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(
                    value: 'tourism',
                    child: Text('LGU Admin'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _role = v ?? _role),
              ),
              if (!_editing) ...[
                TextField(
                  controller: _password,
                  enabled: !_saving,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Temporary Password',
                    helperText: '8+ characters with upper, lower, and a number',
                  ),
                ),
                TextField(
                  controller: _confirm,
                  enabled: !_saving,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? (_editing ? 'Saving…' : 'Creating Account…')
                : (_editing ? 'Save changes' : 'Create Account'),
          ),
        ),
      ],
    );
  }
}

// ─── User Accounts ───────────────────────────────────────────────────────────

class _UserAccountsTab extends StatefulWidget {
  const _UserAccountsTab();

  @override
  State<_UserAccountsTab> createState() => _UserAccountsTabState();
}

class _UserAccountsTabState extends State<_UserAccountsTab> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _accounts = const [];
  String _status = 'All';
  int _page = 0;
  bool _hasMore = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 0}) async {
    setState(() {
      _loading = true;
      _error = null;
      _page = page;
    });
    try {
      final result = await OptacaAccountAdminService.listAccounts(
        accountType: 'tourist',
        search: _search.text.trim(),
        status: _status == 'All' ? '' : _status.toLowerCase(),
        page: page,
        pageSize: 25,
      );
      if (!mounted) return;
      setState(() {
        _accounts = result.accounts;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } on OptacaAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load user accounts.';
      });
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (success != null) await _showSnack(context, success);
      await _load(page: _page);
    } on OptacaAccountException catch (e) {
      if (!mounted) return;
      await _showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _directResetPassword(Map<String, dynamic> account) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdminDirectResetPasswordDialog(account: account),
    );
    if (ok == true && mounted) {
      await _showSnack(context, 'Password successfully reset.');
      await _load(page: _page);
    }
  }

  Future<void> _sendPasswordResetEmail(Map<String, dynamic> account) async {
    await _run(
      () => OptacaAccountAdminService.call({
        'action': 'sendPasswordReset',
        'uid': account['uid'],
      }),
      success: 'Password reset email sent.',
    );
  }

  Future<void> _toggle(Map<String, dynamic> account) async {
    final active = _isActiveStatus(account);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(active ? 'Deactivate account' : 'Reactivate account'),
        content: Text(
          active
              ? 'Deactivate ${account['fullName'] ?? account['email']}?\n\n'
                  'Tourist data (itineraries, trips, ratings) is preserved.'
              : 'Reactivate ${account['fullName'] ?? account['email']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(active ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => OptacaAccountAdminService.call({
        'action': 'setStatus',
        'uid': account['uid'],
        'active': !active,
      }),
      success: active ? 'User deactivated.' : 'User reactivated.',
    );
  }

  Widget _userActionsMenu(Map<String, dynamic> account) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      enabled: !_busy,
      onSelected: (value) {
        switch (value) {
          case 'password':
            _directResetPassword(account);
          case 'email_reset':
            _sendPasswordResetEmail(account);
          case 'toggle':
            _toggle(account);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'password', child: Text('Reset Password')),
        const PopupMenuItem(
          value: 'email_reset',
          child: Text('Send reset email'),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Text(
            _isActiveStatus(account)
                ? 'Deactivate Account'
                : 'Reactivate Account',
          ),
        ),
      ],
      child: const Icon(Icons.more_vert_rounded),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _tabListPadding(context),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: OptacaPortalUi.card(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final compact = _isCompactWidth(maxW);
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: compact ? maxW : _toolbarFieldWidth(maxW, 320),
                    child: TextField(
                      controller: _search,
                      decoration: OptacaPortalUi.searchDecoration(
                        hint: 'Search name or email',
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  SizedBox(
                    width: compact
                        ? _toolbarFieldWidth(maxW, 160)
                        : _toolbarFieldWidth(maxW, 150),
                    child: DropdownButtonFormField<String>(
                      initialValue: _status,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(value: 'Active', child: Text('Active')),
                        DropdownMenuItem(
                          value: 'Deactivated',
                          child: Text('Deactivated'),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() => _status = v ?? 'All');
                        _load();
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _busy ? null : () => _load(page: _page),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Column(
            children: [
              OptacaEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load users',
                message: _error!,
              ),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          )
        else if (_accounts.isEmpty)
          const OptacaEmptyState(
            icon: Icons.people_outline_rounded,
            title: 'No user accounts found',
            message: 'Registered tourist accounts from Firebase appear here.',
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              if (_isCompactWidth(constraints.maxWidth)) {
                return Column(
                  children: [
                    for (final account in _accounts) ...[
                      _accountInfoCard(
                        title: (account['fullName'] ?? 'Tourist').toString(),
                        badge: _statusBadge(_isActiveStatus(account)),
                        details: [
                          ('Email', (account['email'] ?? '—').toString()),
                          ('Role', 'Tourist'),
                          (
                            'Registered',
                            _formatDate(account['createdAtMs']),
                          ),
                        ],
                        trailing: _userActionsMenu(account),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              return _responsiveAccountTable(
                headers: const [
                  'Full Name',
                  'Email Address',
                  'Role',
                  'Status',
                  'Registered Date',
                  'Actions',
                ],
                flexes: const [2, 3, 1, 1, 2, 1],
                rows: _accounts,
                buildCells: (account) => [
                  _ellipsize((account['fullName'] ?? '—').toString()),
                  _ellipsize((account['email'] ?? '—').toString()),
                  _ellipsize('Tourist'),
                  _statusBadge(_isActiveStatus(account)),
                  _ellipsize(_formatDate(account['createdAtMs'])),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _userActionsMenu(account),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _paginationBar(
            page: _page,
            hasMore: _hasMore,
            busy: _busy,
            onPrev: _page == 0 || _busy ? null : () => _load(page: _page - 1),
            onNext: !_hasMore || _busy ? null : () => _load(page: _page + 1),
          ),
        ],
      ],
    );
  }
}

// ─── Direct admin password reset modal ───────────────────────────────────────

class _AdminDirectResetPasswordDialog extends StatefulWidget {
  const _AdminDirectResetPasswordDialog({required this.account});

  final Map<String, dynamic> account;

  @override
  State<_AdminDirectResetPasswordDialog> createState() =>
      _AdminDirectResetPasswordDialogState();
}

class _AdminDirectResetPasswordDialogState
    extends State<_AdminDirectResetPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _accountName {
    final name = (widget.account['fullName'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return (widget.account['email'] ?? 'Account').toString();
  }

  String get _email => (widget.account['email'] ?? '').toString();

  String? _passwordHint(String value) {
    if (value.isEmpty) return null;
    final checks = <String>[];
    if (value.length < 8) checks.add('8+ characters');
    if (!RegExp(r'[A-Z]').hasMatch(value)) checks.add('uppercase');
    if (!RegExp(r'[a-z]').hasMatch(value)) checks.add('lowercase');
    if (!RegExp(r'[0-9]').hasMatch(value)) checks.add('a number');
    if (checks.isEmpty) return 'Strong enough for admin reset';
    return 'Still need: ${checks.join(', ')}';
  }

  Future<void> _submit() async {
    if (_saving) return;
    final password = _password.text;
    final confirm = _confirm.text;
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    try {
      OptacaAccountAdminService.assertPasswordStrength(password);
    } on OptacaAccountException catch (e) {
      setState(() => _error = e.message);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm password reset'),
        content: Text(
          'Reset the password for $_accountName ($_email)?\n\n'
          'Their current sessions will be signed out. They must change this '
          'password on next login. No email or OTP is sent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await OptacaAccountAdminService.resetAccountPassword(
        uid: (widget.account['uid'] ?? '').toString(),
        newPassword: password,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on OptacaAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not reset password.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = _passwordHint(_password.text);
    final matchOk =
        _confirm.text.isEmpty || _confirm.text == _password.text;
    return AlertDialog(
      title: const Text('Reset Password'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48).clamp(280.0, 460.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Assign a new password directly. The account holder does not '
                'need email verification, OTP, or their old password.',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 14),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Account Name',
                  border: OutlineInputBorder(),
                ),
                child: Text(_accountName),
              ),
              const SizedBox(height: 10),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  border: OutlineInputBorder(),
                ),
                child: Text(_email.isEmpty ? '—' : _email),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _password,
                enabled: !_saving,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'New Password',
                  helperText: hint ?? '8+ characters with upper, lower, and a number',
                  helperMaxLines: 2,
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                    onPressed: _saving
                        ? null
                        : () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              TextField(
                controller: _confirm,
                enabled: !_saving,
                obscureText: _obscureConfirm,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  errorText: matchOk ? null : 'Passwords do not match',
                  suffixIcon: IconButton(
                    tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                    onPressed: _saving
                        ? null
                        : () => setState(
                              () => _obscureConfirm = !_obscureConfirm,
                            ),
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || !matchOk ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Reset Password'),
        ),
      ],
    );
  }
}

// ─── Activity Logs ───────────────────────────────────────────────────────────

class _ActivityLogsTab extends StatefulWidget {
  const _ActivityLogsTab();

  @override
  State<_ActivityLogsTab> createState() => _ActivityLogsTabState();
}

class _ActivityLogsTabState extends State<_ActivityLogsTab> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = const [];
  String _action = 'All';

  static const _actions = [
    'All',
    'LGU Account Created',
    'LGU Account Updated',
    'LGU Password Reset Requested',
    'LGU Password Changed by Administrator',
    'LGU Account Deactivated',
    'LGU Account Reactivated',
    'User Password Reset Requested',
    'User Password Changed by Administrator',
    'User Account Deactivated',
    'User Account Reactivated',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logs = await OptacaAccountAdminService.listActivity(
        actionFilter: _action == 'All' ? '' : _action,
        pageSize: 80,
      );
      final q = _search.text.trim().toLowerCase();
      final filtered = q.isEmpty
          ? logs
          : logs.where((row) {
              return row.values.any(
                (v) => v.toString().toLowerCase().contains(q),
              );
            }).toList();
      if (!mounted) return;
      setState(() {
        _logs = filtered;
        _loading = false;
      });
    } on OptacaAccountException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Soft-fail: empty audit trail is normal until account actions run.
        _logs = const [];
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _tabListPadding(context),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: OptacaPortalUi.card(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final compact = _isCompactWidth(maxW);
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: compact ? maxW : _toolbarFieldWidth(maxW, 260),
                    child: TextField(
                      controller: _search,
                      decoration: OptacaPortalUi.searchDecoration(
                        hint: 'Search logs',
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  SizedBox(
                    width: compact ? maxW : _toolbarFieldWidth(maxW, 320),
                    child: DropdownButtonFormField<String>(
                      initialValue: _action,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Action',
                        isDense: true,
                      ),
                      items: [
                        for (final a in _actions)
                          DropdownMenuItem(
                            value: a,
                            child: Text(a, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() => _action = v ?? 'All');
                        _load();
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Column(
            children: [
              OptacaEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load logs',
                message: _error!,
              ),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          )
        else if (_logs.isEmpty)
          const OptacaEmptyState(
            icon: Icons.history_rounded,
            title: 'No activity yet',
            message:
                'Account management actions performed by OPTACA administrators appear here.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              if (_isCompactWidth(constraints.maxWidth)) {
                return Column(
                  children: [
                    for (final log in _logs) ...[
                      _accountInfoCard(
                        title: (log['action'] ?? 'Activity').toString(),
                        badge: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: OptacaAdminTheme.lightOrange,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            (log['result'] ?? '—').toString(),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: OptacaAdminTheme.primary,
                            ),
                          ),
                        ),
                        details: [
                          ('When', _formatDate(log['timestampMs'])),
                          ('Admin', _adminLabel(log).replaceAll('\n', ' · ')),
                          (
                            'Target',
                            (log['targetEmail'] ?? '—').toString(),
                          ),
                          (
                            'Type',
                            (log['accountType'] ?? '—').toString(),
                          ),
                        ],
                        trailing: const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              return _responsiveAccountTable(
                headers: const [
                  'Date and Time',
                  'Administrator',
                  'Target Email',
                  'Account Type',
                  'Action',
                  'Result',
                ],
                flexes: const [2, 2, 3, 1, 2, 1],
                rows: _logs,
                buildCells: (log) => [
                  _ellipsize(_formatDate(log['timestampMs'])),
                  _ellipsize(
                    _adminLabel(log).replaceAll('\n', ' · '),
                    maxLines: 2,
                  ),
                  _ellipsize((log['targetEmail'] ?? '—').toString()),
                  _ellipsize((log['accountType'] ?? '—').toString()),
                  _ellipsize((log['action'] ?? '—').toString(), maxLines: 2),
                  _ellipsize((log['result'] ?? '—').toString()),
                ],
              );
            },
          ),
      ],
    );
  }
}
