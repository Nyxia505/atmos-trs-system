import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/services/provincial_tourism_service.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';
import 'package:atmos_trs_system/widgets/dot_report_export_panel.dart';

/// Province-wide DOT Excel and PDF forms for the OPTACA Portal Reports tab.
/// Same panel as Provincial Tourism → DOT Reports.
class OptacaPortalDotReports extends StatefulWidget {
  const OptacaPortalDotReports({super.key});

  @override
  State<OptacaPortalDotReports> createState() => _OptacaPortalDotReportsState();
}

class _OptacaPortalDotReportsState extends State<OptacaPortalDotReports> {
  final _service = ProvincialTourismService();
  List<Map<String, dynamic>> _tourists = const [];
  List<Map<String, dynamic>> _checkIns = const [];
  List<Map<String, dynamic>> _spots = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await _service.loadSnapshot(includeCheckIns: true);
      if (!mounted) return;
      setState(() {
        _tourists = snap.tourists;
        _checkIns = snap.checkIns;
        _spots = snap.spots;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('OptacaPortalDotReports: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load DOT report data.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(_error!),
      );
    }
    final catalog = [
      for (final s in _spots)
        DotVar2SpotCatalogEntry(
          spotId: s['id']?.toString() ?? '',
          name: s['name']?.toString() ?? 'Unknown',
          dotAttractionCode: s['dotAttractionCode']?.toString() ?? '',
          municipalityId: ProvincialTourismService.municipalityIdOf(s),
          municipalityName: ProvincialTourismService.municipalityNameOf(
            ProvincialTourismService.municipalityIdOf(s),
          ),
          status: s['status']?.toString() ?? '',
        ),
    ];
    final width = MediaQuery.sizeOf(context).width;
    return DotReportExportPanel(
          primaryColor: AppTheme.brandOrange,
          textDark: GovernorDashboardTokens.text,
          textMuted: GovernorDashboardTokens.subtitle,
          borderColor: GovernorDashboardTokens.border,
          scopeLabel: 'Misamis Occidental (OPTACA)',
          scopeSlug: 'misamis_occidental_optaca',
          isProvincial: true,
          isMobile: width < 900,
          checkIns: _checkIns,
          tourists: _tourists,
          catalogSpots: catalog,
          wrapPanel: (child) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: GovernorDashboardTokens.card,
              borderRadius: BorderRadius.circular(
                GovernorDashboardTokens.radiusCard,
              ),
              border: Border.all(color: GovernorDashboardTokens.border),
              boxShadow: GovernorDashboardTokens.cardShadow,
            ),
            child: child,
          ),
    );
  }
}
