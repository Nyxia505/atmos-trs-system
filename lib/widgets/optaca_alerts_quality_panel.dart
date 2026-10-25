import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/models/tourist_destination_detail.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/screens/tourist_destination_detail_screen.dart';
import 'package:atmos_trs_system/services/optaca_data_quality_audit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// OPTACA Alerts & Quality — live audit of ATMOS TRS + Trip Planner records.
class OptacaAlertsQualityPanel extends StatefulWidget {
  const OptacaAlertsQualityPanel({
    super.key,
    this.spotsCache,
    this.checkInsCache,
    this.announcementsCache,
    this.timeFilter = 'This Month',
    this.acknowledgedIds = const {},
    this.onAcknowledge,
    this.showTimeFilter = false,
    this.timeFilterWidget,
  });

  final List<Map<String, dynamic>>? spotsCache;
  final List<Map<String, dynamic>>? checkInsCache;
  final List<Map<String, dynamic>>? announcementsCache;
  final String timeFilter;
  final Set<String> acknowledgedIds;
  final Future<void> Function(String alertId)? onAcknowledge;
  final bool showTimeFilter;
  final Widget? timeFilterWidget;

  @override
  State<OptacaAlertsQualityPanel> createState() =>
      _OptacaAlertsQualityPanelState();
}

class _OptacaAlertsQualityPanelState extends State<OptacaAlertsQualityPanel> {
  final _search = TextEditingController();
  OptacaQualityAuditResult? _result;
  bool _loading = true;
  String? _error;

  String _municipality = 'All';
  String _system = 'All';
  String _issueType = 'All';
  String _severity = 'All';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _runAudit();
  }

  @override
  void didUpdateWidget(covariant OptacaAlertsQualityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeFilter != widget.timeFilter ||
        oldWidget.spotsCache != widget.spotsCache ||
        oldWidget.acknowledgedIds != widget.acknowledgedIds) {
      _runAudit();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _runAudit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await OptacaDataQualityAudit.run(
        spotsCache: widget.spotsCache,
        checkInsCache: widget.checkInsCache,
        announcementsCache: widget.announcementsCache,
        timeFilter: widget.timeFilter,
        acknowledgedIds: widget.acknowledgedIds,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<OptacaQualityIssue> get _filtered {
    final all = _result?.issues ?? const <OptacaQualityIssue>[];
    final q = _query.trim().toLowerCase();
    return [
      for (final i in all)
        if ((_municipality == 'All' || i.municipalityName == _municipality) &&
            (_system == 'All' || i.system == _system) &&
            (_issueType == 'All' || i.issueType == _issueType) &&
            (_severity == 'All' || i.severity.name == _severity.toLowerCase()) &&
            (q.isEmpty ||
                i.recordName.toLowerCase().contains(q) ||
                i.issue.toLowerCase().contains(q) ||
                i.municipalityName.toLowerCase().contains(q) ||
                i.issueType.toLowerCase().contains(q)))
          i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final filtered = _filtered;
    final wide = MediaQuery.sizeOf(context).width >= 960;

    return RefreshIndicator(
      onRefresh: _runAudit,
      color: GovernorDashboardTokens.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alerts & Quality',
                      style: GovernorDashboardTokens.heading(size: 20),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r == null
                          ? 'Scanning tourist spots, featured destinations, and events…'
                          : 'Live audit of ${r.spotCount} tourist_spots + Trip Planner records'
                              '${r.loadWarnings.isEmpty ? '' : ' · ${r.loadWarnings.join(' ')}'}',
                      style: GovernorDashboardTokens.body(size: 12.5),
                    ),
                  ],
                ),
              ),
              if (widget.timeFilterWidget != null) widget.timeFilterWidget!,
              IconButton(
                tooltip: 'Re-scan',
                onPressed: _loading ? null : _runAudit,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading && r == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _panel(
              Text('Audit failed: $_error',
                  style: GovernorDashboardTokens.body()),
            )
          else ...[
            _kpiRow(r!),
            const SizedBox(height: 14),
            _filtersBar(),
            const SizedBox(height: 12),
            Text(
              '${filtered.length} issue${filtered.length == 1 ? '' : 's'}'
              '${filtered.length == (r.total) ? '' : ' (of ${r.total})'}',
              style: GovernorDashboardTokens.body(size: 12.5),
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              _panel(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        size: 40,
                        color: GovernorDashboardTokens.primary,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        r.total == 0
                            ? 'No data-quality issues in scanned records.'
                            : 'No issues match the current filters.',
                        style: GovernorDashboardTokens.sectionTitle(),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'QR checks use qrValue / qr_payload the same way LGU enrollment and tourist check-in do.',
                        style: GovernorDashboardTokens.body(size: 12.5),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else if (wide)
              _table(filtered)
            else
              ...filtered.map(_issueCard),
          ],
        ],
      ),
    );
  }

  Widget _kpiRow(OptacaQualityAuditResult r) {
    Widget card({
      required String title,
      required int value,
      required Color accent,
      required IconData icon,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: GovernorDashboardTokens.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$value',
                      style: GovernorDashboardTokens.heading(size: 18),
                    ),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GovernorDashboardTokens.body(size: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final children = [
      card(
        title: 'Total data issues',
        value: r.total,
        accent: GovernorDashboardTokens.primary,
        icon: Icons.warning_amber_rounded,
      ),
      card(
        title: 'Missing QR codes',
        value: r.countBucket(OptacaIssueBucket.missingQr),
        accent: const Color(0xFFDC2626),
        icon: Icons.qr_code_2_rounded,
      ),
      card(
        title: 'Missing images',
        value: r.countBucket(OptacaIssueBucket.missingImage),
        accent: const Color(0xFFEA580C),
        icon: Icons.image_not_supported_outlined,
      ),
      card(
        title: 'Location issues',
        value: r.countBucket(OptacaIssueBucket.location),
        accent: const Color(0xFF2563EB),
        icon: Icons.wrong_location_outlined,
      ),
      card(
        title: 'Other data issues',
        value: r.countBucket(OptacaIssueBucket.other),
        accent: const Color(0xFF7C3AED),
        icon: Icons.fact_check_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 900) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i += 2)
                Padding(
                  padding: EdgeInsets.only(bottom: i + 2 < children.length ? 8 : 0),
                  child: Row(
                    children: [
                      children[i],
                      const SizedBox(width: 8),
                      if (i + 1 < children.length)
                        children[i + 1]
                      else
                        const Spacer(),
                    ],
                  ),
                ),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              children[i],
            ],
          ],
        );
      },
    );
  }

  Widget _filtersBar() {
    final munis = [
      'All',
      ...getMisamisOccidentalMunicipalities().map((m) => m.name),
    ];
    final issueTypes = <String>{
      'All',
      for (final i in _result?.issues ?? const <OptacaQualityIssue>[])
        i.issueType,
    }.toList()
      ..sort();

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: GovernorDashboardTokens.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: GovernorDashboardTokens.border),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GovernorDashboardTokens.border),
      ),
      child: Column(
        children: [
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            decoration: deco('Search').copyWith(
              hintText: 'Search spot, destination, or issue',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              labelText: null,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final fields = [
                DropdownButtonFormField<String>(
                  initialValue: _municipality,
                  isExpanded: true,
                  decoration: deco('Municipality'),
                  items: [
                    for (final m in munis)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) =>
                      setState(() => _municipality = v ?? 'All'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _system,
                  isExpanded: true,
                  decoration: deco('System'),
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('All')),
                    DropdownMenuItem(
                        value: 'ATMOS TRS', child: Text('ATMOS TRS')),
                    DropdownMenuItem(
                        value: 'Trip Planner', child: Text('Trip Planner')),
                  ],
                  onChanged: (v) => setState(() => _system = v ?? 'All'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: issueTypes.contains(_issueType)
                      ? _issueType
                      : 'All',
                  isExpanded: true,
                  decoration: deco('Issue type'),
                  items: [
                    for (final t in issueTypes)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) =>
                      setState(() => _issueType = v ?? 'All'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _severity,
                  isExpanded: true,
                  decoration: deco('Severity'),
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('All')),
                    DropdownMenuItem(
                        value: 'Critical', child: Text('Critical')),
                    DropdownMenuItem(
                        value: 'Warning', child: Text('Warning')),
                    DropdownMenuItem(value: 'Info', child: Text('Info')),
                  ],
                  onChanged: (v) =>
                      setState(() => _severity = v ?? 'All'),
                ),
              ];
              if (c.maxWidth < 720) {
                return Column(
                  children: [
                    for (var i = 0; i < fields.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      fields[i],
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: fields[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _table(List<OptacaQualityIssue> rows) {
    final headStyle = GovernorDashboardTokens.sectionTitle(
      size: 11,
      color: GovernorDashboardTokens.subtitle,
    );
    Widget head(String t, int flex) => Expanded(
          flex: flex,
          child: Text(t.toUpperCase(), style: headStyle),
        );

    return _panel(
      Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: GovernorDashboardTokens.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                head('Municipality', 3),
                head('System', 2),
                head('Record', 3),
                head('Issue', 4),
                head('Severity', 2),
                head('Status', 2),
                head('Action', 2),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final i in rows) _tableRow(i),
        ],
      ),
      padding: const EdgeInsets.all(12),
    );
  }

  Widget _tableRow(OptacaQualityIssue i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GovernorDashboardTokens.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Text(
                i.municipalityName.isEmpty ? '—' : i.municipalityName,
                style: GovernorDashboardTokens.body(size: 12.5),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(i.system,
                  style: GovernorDashboardTokens.body(size: 12.5)),
            ),
            Expanded(
              flex: 3,
              child: Text(
                i.recordName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GovernorDashboardTokens.sectionTitle(size: 12.5),
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.issueType,
                      style: GovernorDashboardTokens.sectionTitle(size: 12)),
                  Text(i.issue,
                      style: GovernorDashboardTokens.body(size: 11.5)),
                ],
              ),
            ),
            Expanded(flex: 2, child: Align(
              alignment: Alignment.centerLeft,
              child: _severityChip(i.severity),
            )),
            Expanded(
              flex: 2,
              child: Text(i.status,
                  style: GovernorDashboardTokens.body(size: 12.5)),
            ),
            Expanded(
              flex: 2,
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => _openRecord(i),
                    child: const Text('View'),
                  ),
                  if (widget.onAcknowledge != null)
                    TextButton(
                      onPressed: () async {
                        await widget.onAcknowledge!(i.id);
                        await _runAudit();
                      },
                      child: const Text('Ack'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _issueCard(OptacaQualityIssue i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _severityChip(i.severity),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    i.recordName,
                    style: GovernorDashboardTokens.sectionTitle(size: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${i.municipalityName.isEmpty ? 'Unassigned' : i.municipalityName} · ${i.system}',
              style: GovernorDashboardTokens.body(size: 12),
            ),
            const SizedBox(height: 6),
            Text(i.issueType,
                style: GovernorDashboardTokens.sectionTitle(size: 12.5)),
            Text(i.issue, style: GovernorDashboardTokens.body(size: 12.5)),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => _openRecord(i),
                  child: const Text('View record'),
                ),
                if (widget.onAcknowledge != null)
                  TextButton(
                    onPressed: () async {
                      await widget.onAcknowledge!(i.id);
                      await _runAudit();
                    },
                    child: const Text('Acknowledge'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _severityChip(OptacaIssueSeverity s) {
    final color = switch (s) {
      OptacaIssueSeverity.critical => GovernorDashboardTokens.danger,
      OptacaIssueSeverity.warning => const Color(0xFFEA580C),
      OptacaIssueSeverity.info => const Color(0xFF2563EB),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        s.name.toUpperCase(),
        style: GovernorDashboardTokens.sectionTitle(size: 10.5, color: color),
      ),
    );
  }

  Future<void> _openRecord(OptacaQualityIssue issue) async {
    final id = issue.recordId.trim();
    if (id.isEmpty) return;

    // Prefer tourist_spots detail (shared ATMOS + Trip Planner catalog).
    try {
      final doc =
          await FirebaseFirestore.instance.collection('tourist_spots').doc(id).get();
      if (doc.exists && doc.data() != null && mounted) {
        final fs = TouristSpotFirestore.fromFirestore(doc.data()!, doc.id);
        final detail = TouristDestinationDetail.fromFirestoreSpot(fs);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TouristDestinationDetailScreen(
              destination: detail,
              firestoreSpot: fs,
            ),
          ),
        );
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(issue.recordName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${issue.system} · ${issue.issueType}'),
            const SizedBox(height: 8),
            Text(issue.issue),
            const SizedBox(height: 8),
            Text(
              'LGU: ${issue.municipalityName.isEmpty ? '—' : issue.municipalityName}',
              style: GovernorDashboardTokens.body(size: 12.5),
            ),
            Text(
              'Record id: ${issue.recordId}',
              style: GovernorDashboardTokens.body(size: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _panel(Widget child, {EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GovernorDashboardTokens.border),
      ),
      child: child,
    );
  }
}
