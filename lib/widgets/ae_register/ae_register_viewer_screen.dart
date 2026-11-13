import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_register_workspace.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/establishment_dashboard_components.dart';
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

  void _goBack() => Navigator.of(context).pop();

  Widget _viewerBackBar() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _goBack,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFF97316),
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFF97316), width: 1.4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            minimumSize: const Size(0, 42),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text(
            'Back',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final schema = AeRegisterSchema.forCategory(p.category);
    final title = p.aeName.isNotEmpty ? p.aeName : 'Establishment';
    final subtitle = switch (_section) {
      AeViewerSection.register => [
          'DOT Register (read-only)',
          if (p.municipality.isNotEmpty) p.municipality,
          if (schema.tracksRooms && p.totalRooms > 0) '${p.totalRooms} rooms',
        ].join(' · '),
      AeViewerSection.events => [
          'Events (MICE, read-only)',
          if (p.municipality.isNotEmpty) p.municipality,
        ].join(' · '),
      AeViewerSection.insights => [
          'Insights (read-only)',
          if (p.municipality.isNotEmpty) p.municipality,
          if (schema.tracksRooms && p.totalRooms > 0) '${p.totalRooms} rooms',
        ].join(' · '),
    };

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _OrangeEstablishmentHeader(
            title: title,
            subtitle: subtitle,
            showRegister: true,
            showInsights: true,
            showEvents: widget.showEvents,
            selected: _section,
            onSelectRegister: () => setState(() => _section = AeViewerSection.register),
            onSelectInsights: () => setState(() => _section = AeViewerSection.insights),
            onSelectEvents: () => setState(() => _section = AeViewerSection.events),
          ),
          Expanded(
            child: switch (_section) {
              AeViewerSection.insights => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _viewerBackBar(),
                    Expanded(
                      child: EstablishmentInsightsBoard(
                        profile: p,
                        schema: schema,
                        embedded: true,
                      ),
                    ),
                  ],
                ),
              AeViewerSection.events => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _viewerBackBar(),
                    Expanded(
                      child: MiceRegisterWorkspace(
                        profile: p,
                        readOnly: true,
                        initialYear: widget.initialYear,
                        initialMonth: widget.initialMonth,
                      ),
                    ),
                  ],
                ),
              AeViewerSection.register => AeRegisterWorkspace(
                  profile: p,
                  schema: schema,
                  readOnly: true,
                  initialYear: widget.initialYear,
                  initialMonth: widget.initialMonth,
                  onBack: _goBack,
                ),
            },
          ),
        ],
      ),
    );
  }
}

/// Shared orange brand header: centered title, left mark, right nav pills.
class _OrangeEstablishmentHeader extends StatelessWidget {
  const _OrangeEstablishmentHeader({
    required this.title,
    required this.subtitle,
    required this.showRegister,
    required this.showInsights,
    required this.selected,
    this.showEvents = false,
    this.onSelectRegister,
    this.onSelectInsights,
    this.onSelectEvents,
    this.leading,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final bool showRegister;
  final bool showInsights;
  final bool showEvents;
  final AeViewerSection selected;
  final VoidCallback? onSelectRegister;
  final VoidCallback? onSelectInsights;
  final VoidCallback? onSelectEvents;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AeDashTokens.bannerGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33EA580C),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: AeBannerBackdrop()),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final compact = c.maxWidth < 720;
                  final titleBlock = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: compact ? 17 : 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                          height: 1.2,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                        ),
                      ],
                    ],
                  );

                  final nav = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      if (showRegister)
                        _HeaderNavPill(
                          icon: Icons.folder_outlined,
                          label: 'Register',
                          selected: selected == AeViewerSection.register,
                          onTap: onSelectRegister,
                        ),
                      if (showEvents)
                        _HeaderNavPill(
                          icon: Icons.celebration_outlined,
                          label: 'Events',
                          selected: selected == AeViewerSection.events,
                          onTap: onSelectEvents,
                        ),
                      if (showInsights)
                        _HeaderNavPill(
                          icon: Icons.show_chart_rounded,
                          label: 'Insights',
                          selected: selected == AeViewerSection.insights,
                          onTap: onSelectInsights,
                        ),
                      if (trailing != null) trailing!,
                    ],
                  );

                  if (compact) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            leading ?? _buildingMark(),
                            const Spacer(),
                            nav,
                          ],
                        ),
                        const SizedBox(height: 12),
                        titleBlock,
                      ],
                    );
                  }

                  return SizedBox(
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 160),
                          child: titleBlock,
                        ),
                        Row(
                          children: [
                            leading ?? _buildingMark(),
                            const Spacer(),
                            nav,
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildingMark() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.apartment_rounded, color: Color(0xFFF97316), size: 22),
    );
  }
}

class _HeaderNavPill extends StatelessWidget {
  const _HeaderNavPill({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.45),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? const Color(0xFFF97316) : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? const Color(0xFF1F2937) : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
