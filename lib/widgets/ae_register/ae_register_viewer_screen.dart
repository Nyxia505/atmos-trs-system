import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_register_workspace.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_insights_board.dart';
import 'package:atmos_trs_system/widgets/mice_register/mice_register_workspace.dart';

enum AeViewerSection { register, events, insights }

/// Read-only register, MICE events + Insights for LGU / OPTACA / Governor.
class AeRegisterViewerScreen extends StatefulWidget {
  const AeRegisterViewerScreen({
    super.key,
    required this.profile,
    this.initialYear,
    this.initialMonth,
    this.initialSection = AeViewerSection.register,
    this.showEvents = false,
  });

  final AeRegisterProfile profile;
  final int? initialYear;
  final int? initialMonth;
  final AeViewerSection initialSection;

  /// Venue hosts MICE events (shows the CUS events segment).
  final bool showEvents;

  /// Builds a viewer profile from registry fields (type defaults from category).
  static AeRegisterProfile profileFor({
    required String aeId,
    required String aeName,
    required String category,
    String municipalityId = '',
    String municipality = '',
    int? totalRooms,
    String aeType = '',
    String classificationCode = '',
  }) =>
      AeRegisterProfile.fromRegistry(
        aeId: aeId,
        aeName: aeName,
        category: category,
        municipalityId: municipalityId,
        municipality: municipality,
        totalRooms: totalRooms,
        aeType: aeType,
        classificationCode: classificationCode,
      );

  static Future<void> open(
    BuildContext context, {
    required AeRegisterProfile profile,
    int? year,
    int? month,
    bool insights = false,
    bool events = false,
    bool showEvents = false,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AeRegisterViewerScreen(
            profile: profile,
            initialYear: year,
            initialMonth: month,
            showEvents: showEvents || events,
            initialSection: events
                ? AeViewerSection.events
                : (insights ? AeViewerSection.insights : AeViewerSection.register),
          ),
        ),
      );

  @override
  State<AeRegisterViewerScreen> createState() => _AeRegisterViewerScreenState();
}

class _AeRegisterViewerScreenState extends State<AeRegisterViewerScreen> {
  late AeViewerSection _section = widget.initialSection;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final schema = AeRegisterSchema.forCategory(p.category);
    return Scaffold(
      backgroundColor: AeDashTokens.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AeDashTokens.text,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.aeName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AeDashTokens.heading(size: 17)),
            Text(
              [
                _section == AeViewerSection.events ? 'MICE events (read-only)' : 'DOT register (read-only)',
                if (p.municipality.isNotEmpty) p.municipality,
                if (schema.tracksRooms && p.totalRooms > 0) '${p.totalRooms} rooms',
              ].join(' · '),
              style: AeDashTokens.body(size: 12),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<AeViewerSection>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(
                  value: AeViewerSection.register,
                  icon: Icon(Icons.table_chart_rounded, size: 18),
                  label: Text('Register'),
                ),
                if (widget.showEvents)
                  const ButtonSegment(
                    value: AeViewerSection.events,
                    icon: Icon(Icons.celebration_rounded, size: 18),
                    label: Text('Events'),
                  ),
                const ButtonSegment(
                  value: AeViewerSection.insights,
                  icon: Icon(Icons.insights_rounded, size: 18),
                  label: Text('Insights'),
                ),
              ],
              selected: {_section},
              onSelectionChanged: (s) => setState(() => _section = s.first),
            ),
          ),
        ],
      ),
      body: switch (_section) {
        AeViewerSection.insights => EstablishmentInsightsBoard(profile: p, schema: schema, embedded: true),
        AeViewerSection.events => MiceRegisterWorkspace(
            profile: p,
            readOnly: true,
            initialYear: widget.initialYear,
            initialMonth: widget.initialMonth,
          ),
        AeViewerSection.register => AeRegisterWorkspace(
            profile: p,
            schema: schema,
            readOnly: true,
            initialYear: widget.initialYear,
            initialMonth: widget.initialMonth,
          ),
      },
    );
  }
}
