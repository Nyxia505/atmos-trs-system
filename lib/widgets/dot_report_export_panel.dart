import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atmos_trs_system/config/mice_event_types.dart';
import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/models/sign_off.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/services/lgu_checkin_report_query.dart';
import 'package:atmos_trs_system/services/sign_off_service.dart';
import 'package:atmos_trs_system/utils/dot_report_entity_scope.dart';
import 'package:atmos_trs_system/utils/dot_report_export_service.dart';
import 'package:atmos_trs_system/utils/dot_report_pdf_export.dart';
import 'package:atmos_trs_system/utils/dot_report_preview.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';
import 'package:atmos_trs_system/utils/ae_register_report_query.dart';
import 'package:atmos_trs_system/utils/mice_report_query.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/pdf_file_download.dart';
import 'package:atmos_trs_system/utils/xlsx_file_download.dart';
import 'package:atmos_trs_system/widgets/atmos_table_kit.dart';

/// Shared DOT / DAE export panel for LGU (municipal) and Governor (provincial).
class DotReportExportPanel extends StatefulWidget {
  const DotReportExportPanel({
    super.key,
    required this.primaryColor,
    required this.textDark,
    required this.textMuted,
    required this.borderColor,
    required this.scopeLabel,
    required this.scopeSlug,
    required this.isProvincial,
    required this.isMobile,
    required this.checkIns,
    required this.tourists,
    required this.catalogSpots,
    this.municipalityId,
    this.parseTimestamp,
    this.wrapPanel,
    this.lockedEstablishment,
    this.allowedFormIds,
    this.extraFillFormsBuilder,
    this.compactChrome = false,
  });

  final Color primaryColor;
  final Color textDark;
  final Color textMuted;
  final Color borderColor;
  final String scopeLabel;
  final String scopeSlug;
  final bool isProvincial;
  final bool isMobile;
  final List<Map<String, dynamic>> checkIns;
  final List<Map<String, dynamic>> tourists;
  final List<DotVar2SpotCatalogEntry> catalogSpots;
  /// LGU municipality id — used for ranged Firestore check-in fetch.
  final String? municipalityId;
  final DateTime? Function(Map<String, dynamic> checkIn)? parseTimestamp;
  final Widget Function(Widget child)? wrapPanel;

  /// Establishment dashboard: scope fixed to this AE (scope pickers hidden).
  final DotReportEntityOption? lockedEstablishment;

  /// Restricts the form list (catalog ids). Null = full catalog.
  final Set<String>? allowedFormIds;

  /// OPTACA portal: optional Events / Matrix Fares fill UI inside entity scope.
  final Widget Function(BuildContext context, DotReportEntityKind kind)?
      extraFillFormsBuilder;

  /// OPTACA portal: hide helper copy that duplicates titles and cards.
  final bool compactChrome;

  @override
  State<DotReportExportPanel> createState() => _DotReportExportPanelState();
}

enum _DotExportOp { excel, pdf, blank }

class _DotReportExportPanelState extends State<DotReportExportPanel> {
  final _service = DotReportExportService();
  final _formSearchController = TextEditingController();
  late DotFormCatalogEntry _selected;
  DateTime? _start;
  DateTime? _end;
  /// Only one export runs at a time; labels/spinners follow this op.
  _DotExportOp? _activeExport;
  bool get _busy => _activeExport != null;
  bool get _excelBusy => _activeExport == _DotExportOp.excel;
  bool get _pdfBusy => _activeExport == _DotExportOp.pdf;
  static const _kPaperPrefKey = 'dot_report_pdf_paper_size';
  DotPdfPaperSize _paperSize = DotPdfPaperSize.a4;
  DotReportPreviewTable? _preview;
  bool _previewLoading = false;
  int _previewSeq = 0;

  /// all | spot | establishment
  DotReportEntityKind _entityKind = DotReportEntityKind.all;
  DotReportEntityOption? _selectedEntity;
  /// Provincial only: narrow spot/AE lists to one LGU (empty = all LGUs).
  String _entityMunicipalityFilter = '';
  List<DotReportEntityOption> _establishments = const [];
  Set<String> _miceVenueIds = const {};
  StreamSubscription<List<EstablishmentRegistryEntry>>? _estSub;

  // CUS MICE options.
  static const _kCusLayoutPrefKey = 'dot_report_cus_layout';
  final Set<MiceCategory> _miceCategories = {};
  bool _miceIncludeDrafts = true;
  CusLayout _cusLayout = CusLayout.summaryAndVenues;
  final _officerController = TextEditingController();
  final _mayorController = TextEditingController();

  bool get _locked => widget.lockedEstablishment != null;
  bool get _isCus => _selected.reportType == DotReportType.cusMice;

  String get _signatoryPrefKey {
    final slug = widget.scopeSlug.trim().isEmpty ? 'default' : widget.scopeSlug.trim();
    return 'dot_report_cus_signatories_$slug';
  }

  List<DotFormCatalogEntry> get _catalog {
    final allowed = widget.allowedFormIds;
    if (allowed == null) return kDotFormCatalog;
    return [for (final f in kDotFormCatalog) if (allowed.contains(f.id)) f];
  }

  /// Spot / municipality-spots scope lists VAR only. Establishment scope lists
  /// DAE and CUS. All spots and establishments lists every family.
  List<DotFormCatalogEntry> get _scopedCatalog {
    final base = _catalog;
    return switch (_entityKind) {
      DotReportEntityKind.spot || DotReportEntityKind.municipalitySpots => [
          for (final f in base)
            if (f.category == DotFormCategory.attraction) f,
        ],
      DotReportEntityKind.establishment => [
          for (final f in base)
            if (f.category == DotFormCategory.accommodation ||
                f.category == DotFormCategory.mice)
              f,
        ],
      DotReportEntityKind.all => base,
    };
  }

  bool get _isAttractionScope =>
      _entityKind == DotReportEntityKind.spot ||
      _entityKind == DotReportEntityKind.municipalitySpots;

  /// Municipality id used for "all spots in municipality" / LGU filter.
  String get _resolvedMunicipalityFilter {
    if (!widget.isProvincial) {
      return normalizeMunicipalityId(widget.municipalityId);
    }
    return normalizeMunicipalityId(_entityMunicipalityFilter);
  }

  String get _resolvedMunicipalityDisplayName {
    final mid = _resolvedMunicipalityFilter;
    if (mid.isNotEmpty) {
      return DotReportEntityScope.municipalityDisplayName(mid);
    }
    if (!widget.isProvincial) return widget.scopeLabel;
    return '';
  }

  void _syncFormToScope() {
    final forms = _scopedCatalog;
    if (forms.isEmpty) return;
    if (forms.any((f) => f.id == _selected.id)) return;
    _selected = forms.first;
    _formSearchController.text = _selected.title;
  }

  @override
  void initState() {
    super.initState();
    final catalog = _catalog;
    _selected = catalog.isEmpty ? kDotFormCatalogById['var2']! : catalog.first;
    _formSearchController.text = _selected.title;
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = DateTime(now.year, now.month, now.day);
    if (_locked) {
      _entityKind = DotReportEntityKind.establishment;
      _selectedEntity = widget.lockedEstablishment;
    } else {
      _subscribeEstablishments();
    }
    _syncFormToScope();
    unawaited(_refreshPreview());
    unawaited(_loadPaperSize());
  }

  Future<void> _loadPaperSize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = DotPdfPaperSizeX.fromName(prefs.getString(_kPaperPrefKey));
    final layout = CusLayout.values.firstWhere(
      (l) => l.name == prefs.getString(_kCusLayoutPrefKey),
      orElse: () => CusLayout.summaryAndVenues,
    );
    final names = prefs.getStringList(_signatoryPrefKey) ?? const [];
    if (!mounted) return;
    setState(() {
      _paperSize = saved;
      _cusLayout = layout;
    });
    if (names.isNotEmpty && _officerController.text.isEmpty) _officerController.text = names.first;
    if (names.length > 1 && _mayorController.text.isEmpty) _mayorController.text = names[1];
  }

  /// Officer / Mayor names are remembered per LGU scope on this device.
  void _saveSignatories() {
    final names = [_officerController.text.trim(), _mayorController.text.trim()];
    unawaited(SharedPreferences.getInstance().then((p) => p.setStringList(_signatoryPrefKey, names)));
  }

  CusExportOptions get _cusOptions => CusExportOptions(
        layout: _cusLayout,
        officerName: _officerController.text.trim(),
        mayorName: _mayorController.text.trim(),
      );

  List<DotPdfSignatory> get _cusSignatories => [
        DotPdfSignatory(role: 'Name of Tourism Officer', name: _officerController.text),
        DotPdfSignatory(role: 'Mayor', name: _mayorController.text),
      ];

  void _onPaperSizeChanged(DotPdfPaperSize? size) {
    if (size == null || size == _paperSize) return;
    setState(() => _paperSize = size);
    unawaited(
      SharedPreferences.getInstance()
          .then((p) => p.setString(_kPaperPrefKey, size.name)),
    );
  }

  Widget _paperSizeField({bool expand = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'PDF Paper Size',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: widget.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<DotPdfPaperSize>(
          key: ValueKey(_paperSize),
          initialValue: _paperSize,
          isExpanded: expand,
          isDense: true,
          onChanged: _busy ? null : _onPaperSizeChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            prefixIcon: Icon(
              Icons.description_outlined,
              size: 18,
              color: widget.primaryColor,
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 38, minHeight: 20),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.primaryColor, width: 1.4),
            ),
          ),
          items: [
            for (final p in DotPdfPaperSize.values)
              DropdownMenuItem(
                value: p,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: p.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: widget.textDark,
                        ),
                      ),
                      TextSpan(
                        text: '  ${p.dimensionsLabel}',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.textMuted,
                        ),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(covariant DotReportExportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_locked &&
        (oldWidget.municipalityId != widget.municipalityId ||
            oldWidget.isProvincial != widget.isProvincial)) {
      _subscribeEstablishments();
    }
    if (oldWidget.checkIns.length != widget.checkIns.length ||
        oldWidget.tourists.length != widget.tourists.length ||
        oldWidget.scopeLabel != widget.scopeLabel ||
        oldWidget.catalogSpots.length != widget.catalogSpots.length) {
      unawaited(_refreshPreview());
    }
  }

  @override
  void dispose() {
    _estSub?.cancel();
    _formSearchController.dispose();
    _officerController.dispose();
    _mayorController.dispose();
    _service.dispose();
    super.dispose();
  }

  void _subscribeEstablishments() {
    _estSub?.cancel();
    if (widget.isProvincial) {
      _estSub = EstablishmentApprovalService.watchAll().listen(_onEstablishments);
      return;
    }
    final mid = normalizeMunicipalityId(widget.municipalityId);
    if (mid.isEmpty) {
      setState(() => _establishments = const []);
      return;
    }
    _estSub = EstablishmentApprovalService.watchForMunicipality(mid).listen(_onEstablishments);
  }

  void _onEstablishments(List<EstablishmentRegistryEntry> entries) {
    if (!mounted) return;
    final active = entries.where((e) => e.isActive);
    setState(() {
      _establishments = [
        for (final e in active)
          DotReportEntityOption(
            id: e.id,
            name: e.businessName,
            kind: DotReportEntityKind.establishment,
            municipalityId: e.municipalityId,
            municipalityName: e.municipality,
          ),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _miceVenueIds = {for (final e in active) if (e.hostsMice) e.id};
    });
    unawaited(_refreshPreview());
  }

  List<DotVar2SpotCatalogEntry> get _catalogForMunicipalityFilter {
    final munFilter = normalizeMunicipalityId(_entityMunicipalityFilter);
    if (!widget.isProvincial || munFilter.isEmpty) {
      return widget.catalogSpots;
    }
    final filtered = [
      for (final s in widget.catalogSpots)
        if (_catalogEntryInMunicipality(s, munFilter)) s,
    ];
    // If catalog rows lack municipality metadata, do not silently drop them
    // for single-spot pickers — keep the full list.
    final anyMeta = widget.catalogSpots.any(
      (s) =>
          s.municipalityId.trim().isNotEmpty ||
          s.municipalityName.trim().isNotEmpty,
    );
    return anyMeta ? filtered : widget.catalogSpots;
  }

  bool _catalogEntryInMunicipality(
    DotVar2SpotCatalogEntry s,
    String munFilter,
  ) {
    final mid = normalizeMunicipalityId(s.municipalityId);
    if (mid.isNotEmpty) {
      return municipalityIdsForQuery(munFilter)
          .map(normalizeMunicipalityId)
          .contains(mid);
    }
    final fromName = normalizeMunicipalityId(
      getMunicipalityIdFromName(s.municipalityName),
    );
    return fromName.isNotEmpty && fromName == munFilter;
  }

  /// Eligible spots for the selected municipality (VAR 2 all-spots scope).
  List<DotVar2SpotCatalogEntry> get _eligibleMunicipalitySpots {
    final mid = _resolvedMunicipalityFilter;
    final source = !widget.isProvincial
        ? widget.catalogSpots
        : [
            for (final s in widget.catalogSpots)
              if (mid.isNotEmpty && _catalogEntryInMunicipality(s, mid)) s,
          ];
    return [
      for (final s in source)
        if (s.isEligibleForVar2 &&
            (s.spotId.trim().isNotEmpty || s.name.trim().isNotEmpty))
          s,
    ];
  }

  List<DotReportEntityOption> get _spotOptions {
    final out = <DotReportEntityOption>[];
    for (final s in _catalogForMunicipalityFilter) {
      if (s.spotId.trim().isEmpty && s.name.trim().isEmpty) continue;
      final munId = s.municipalityId.trim().isNotEmpty
          ? s.municipalityId.trim()
          : (widget.isProvincial ? '' : (widget.municipalityId ?? ''));
      final munName = s.municipalityName.trim().isNotEmpty
          ? s.municipalityName.trim()
          : (widget.isProvincial ? '' : widget.scopeLabel);
      out.add(
        DotReportEntityOption(
          id: s.spotId.trim().isNotEmpty ? s.spotId.trim() : s.name.trim(),
          name: s.name.trim().isEmpty ? s.spotId : s.name.trim(),
          kind: DotReportEntityKind.spot,
          municipalityId: munId,
          municipalityName: munName,
        ),
      );
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  List<DotReportEntityOption> get _establishmentOptions {
    final munFilter = normalizeMunicipalityId(_entityMunicipalityFilter);
    final list = [
      for (final e in _establishments)
        if ((!_isCus || _miceVenueIds.contains(e.id)) &&
            (!widget.isProvincial ||
                munFilter.isEmpty ||
                normalizeMunicipalityId(e.municipalityId) == munFilter ||
                normalizeMunicipalityId(
                      getMunicipalityIdFromName(e.municipalityName),
                    ) ==
                    munFilter))
          e,
    ];
    return list;
  }

  String get _effectiveScopeLabel => DotReportEntityScope.labelFor(
        baseLabel: widget.scopeLabel,
        kind: _entityKind,
        entity: _selectedEntity,
        municipalityName: _entityKind == DotReportEntityKind.municipalitySpots
            ? _resolvedMunicipalityDisplayName
            : null,
      );

  String get _effectiveScopeSlug => DotReportEntityScope.slugFor(
        baseSlug: widget.scopeSlug,
        kind: _entityKind,
        entityId: _selectedEntity?.id,
        municipalityId: _entityKind == DotReportEntityKind.municipalitySpots
            ? _resolvedMunicipalityFilter
            : null,
      );

  List<DotVar2SpotCatalogEntry> get _effectiveCatalog {
    if (_entityKind == DotReportEntityKind.municipalitySpots) {
      return _eligibleMunicipalitySpots;
    }
    if (_entityKind != DotReportEntityKind.spot || _selectedEntity == null) {
      return widget.catalogSpots;
    }
    final id = _selectedEntity!.id.toLowerCase();
    final name = _selectedEntity!.name.toLowerCase();
    final matched = [
      for (final s in _catalogForMunicipalityFilter)
        if (s.spotId.trim().toLowerCase() == id ||
            s.name.trim().toLowerCase() == name)
          s,
    ];
    if (matched.isNotEmpty) return matched;
    return [
      DotVar2SpotCatalogEntry(
        spotId: _selectedEntity!.id,
        name: _selectedEntity!.name,
        municipalityId: _selectedEntity!.municipalityId,
        municipalityName: _selectedEntity!.municipalityName,
      ),
    ];
  }

  Future<void> _refreshPreview() async {
    if (_start == null || _end == null) return;
    final seq = ++_previewSeq;
    setState(() => _previewLoading = true);

    try {
      final end = DateTime(_end!.year, _end!.month, _end!.day, 23, 59, 59, 999);
      final checkIns = await _resolveCheckInsForExport(
        start: _start!,
        end: end,
      );
      final aeRegister = await _resolveAeRegisterForDae(
        form: _selected,
        start: _start!,
        end: end,
      );
      final mice = await _resolveMiceForCus(form: _selected, start: _start!, end: end);
      if (!mounted || seq != _previewSeq) return;
      final preview = buildDotReportPreview(
        form: _selected,
        startDate: _start!,
        endDate: end,
        checkIns: checkIns,
        tourists: widget.tourists,
        catalogSpots: _effectiveCatalog,
        scopeLabel: _effectiveScopeLabel,
        parseTimestamp: widget.parseTimestamp,
        aeRegister: aeRegister,
        mice: mice,
      );
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _preview = preview;
        _previewLoading = false;
      });
    } catch (e) {
      debugPrint('[DotReportExportPanel] preview: $e');
      if (!mounted || seq != _previewSeq) return;
      setState(() {
        _preview = null;
        _previewLoading = false;
      });
    }
  }

  void _onFormSelected(DotFormCatalogEntry form) {
    setState(() {
      if (!_locked) {
        final spotHidesThisForm = _isAttractionScope &&
            form.category != DotFormCategory.attraction;
        final establishmentHidesThisForm =
            _entityKind == DotReportEntityKind.establishment &&
                form.category == DotFormCategory.attraction;
        if (spotHidesThisForm || establishmentHidesThisForm) {
          _entityKind = DotReportEntityKind.all;
          _selectedEntity = null;
        }
      }
      _selected = form;
      _formSearchController.text = form.title;
      if (!_locked &&
          _selectedEntity != null &&
          _entityKind == DotReportEntityKind.establishment &&
          !_establishmentOptions.any((e) => e.id == _selectedEntity!.id)) {
        _selectedEntity = null;
      }
    });
    unawaited(_refreshPreview());
  }

  void _onDateChanged(DateTime d, {required bool isStart}) {
    setState(() {
      if (isStart) {
        _start = d;
      } else {
        _end = d;
      }
    });
    unawaited(_refreshPreview());
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.wrapPanel != null) {
      return widget.wrapPanel!(body);
    }

    // AE dashboard already has the compact orange page header + gray canvas —
    // float section cards directly (no outer white shell).
    if (_locked) return body;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(widget.isMobile ? 18 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: body,
    );
  }

  Widget _sectionCard({required Widget child}) {
    final ae = _locked;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(widget.isMobile ? 14 : 16),
      decoration: BoxDecoration(
        color: ae ? Colors.white : const Color(0xFFFCFCFD),
        borderRadius: BorderRadius.circular(ae ? 16 : 14),
        border: Border.all(color: widget.borderColor.withValues(alpha: 0.95)),
        boxShadow: ae
            ? [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  Widget _sectionHeading({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: widget.primaryColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: widget.primaryColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: widget.textDark,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: widget.textMuted,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    final scopeHint = widget.isProvincial
        ? 'Province-wide best-effort fill: preview every form, then download Excel or PDF.'
        : 'Search any DOT / DAE / MICE form — preview filled data, then download Excel or PDF.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isProvincial) ...[
          _buildProvincialBanner(scopeHint),
          const SizedBox(height: 14),
        ],
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.isProvincial)
                _sectionHeading(
                  icon: Icons.folder_open_rounded,
                  title: 'Official Forms',
                  subtitle: scopeHint,
                )
              else
                _sectionHeading(
                  icon: Icons.description_rounded,
                  title: 'Form Type',
                  subtitle: 'Select the DOT form to generate and export.',
                ),
              SizedBox(height: widget.isProvincial ? 12 : 14),
              if (!widget.isProvincial) ...[
                Text(
                  'Form type',
                  style: TextStyle(
                    color: widget.textDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _buildFormTypeDropdown(),
              const SizedBox(height: 10),
              _buildSelectedFormMeta(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_locked)
          _aeRegisterSourceStrip()
        else
          _sectionCard(
            child: widget.isProvincial
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionHeading(
                        icon: Icons.place_rounded,
                        title: 'Scope (Spot / Establishment)',
                        subtitle:
                            'OPTACA / Governor: pick one spot, all spots in an LGU, or one establishment.',
                      ),
                      const SizedBox(height: 12),
                      _buildEntityScopeFields(),
                    ],
                  )
                : _buildEntityScopeSection(),
          ),
        if (_isCus) ...[
          const SizedBox(height: 12),
          _sectionCard(child: _buildCusOptions()),
        ],
        const SizedBox(height: 12),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeading(
                icon: Icons.calendar_month_rounded,
                title: 'Date Range & Export',
                subtitle:
                    'Choose the reporting window, PDF paper size, then download.',
              ),
              const SizedBox(height: 14),
              _buildExportControls(),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildFilledPreviewSection(),
      ],
    );
  }

  Widget _buildProvincialBanner(String subtitle) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              widget.isMobile ? 14 : 16,
              14,
              widget.isMobile ? 14 : 16,
              14,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFFFFF7ED),
                  Color.lerp(const Color(0xFFFFEDD5), Colors.white, 0.35)!,
                  Colors.white,
                ],
              ),
              border: Border.all(
                color: widget.primaryColor.withValues(alpha: 0.18),
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _sectionHeading(
              icon: Icons.folder_open_rounded,
              title: 'DOT Templates (Province-wide)',
              subtitle: subtitle,
            ),
          ),
          Positioned(
            right: -10,
            bottom: -18,
            child: CustomPaint(
              size: const Size(120, 70),
              painter: _DotPanelWavePainter(
                color: widget.primaryColor.withValues(alpha: 0.10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCusOptions() {
    final label = TextStyle(color: widget.textDark, fontSize: 13, fontWeight: FontWeight.w700);
    final hint = TextStyle(color: widget.textMuted, fontSize: 11.5, height: 1.35);
    InputDecoration deco(String text, IconData icon) => InputDecoration(
          labelText: text,
          isDense: true,
          prefixIcon: Icon(icon, size: 18, color: widget.primaryColor),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        );
    void changed(VoidCallback fn) {
      setState(fn);
      unawaited(_refreshPreview());
    }

    final officer = TextField(
      controller: _officerController,
      enabled: !_busy,
      textCapitalization: TextCapitalization.words,
      onSubmitted: (_) => _saveSignatories(),
      decoration: deco('Name of Tourism Officer', Icons.badge_outlined),
    );
    final mayor = TextField(
      controller: _mayorController,
      enabled: !_busy,
      textCapitalization: TextCapitalization.words,
      onSubmitted: (_) => _saveSignatories(),
      decoration: deco('Mayor', Icons.account_balance_outlined),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('MICE filters & layout', style: label),
        const SizedBox(height: 4),
        Text(
          'Filled from venue event logs (Events tab). Pick categories to narrow the sheet; none selected = all events.',
          style: hint,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in MiceCategory.values)
              FilterChip(
                avatar: Icon(c.icon, size: 16),
                label: Text(c.label),
                selected: _miceCategories.contains(c),
                onSelected: _busy
                    ? null
                    : (on) => changed(() => on ? _miceCategories.add(c) : _miceCategories.remove(c)),
              ),
            if (_miceCategories.isNotEmpty)
              ActionChip(
                avatar: const Icon(Icons.clear_rounded, size: 16),
                label: const Text('All categories'),
                onPressed: _busy ? null : () => changed(_miceCategories.clear),
              ),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _miceIncludeDrafts,
          onChanged: _busy ? null : (v) => changed(() => _miceIncludeDrafts = v),
          title: const Text('Include draft months'),
          subtitle: Text(
            _miceIncludeDrafts
                ? 'Drafts are counted and flagged in ATMOS_GAPS.'
                : 'Only months the venue submitted to the LGU.',
            style: hint,
          ),
        ),
        if (!_locked) ...[
          const SizedBox(height: 4),
          DropdownButtonFormField<CusLayout>(
            key: ValueKey(_cusLayout),
            initialValue: _cusLayout,
            isExpanded: true,
            decoration: deco('Excel layout (several venues)', Icons.table_view_outlined),
            items: [
              for (final l in CusLayout.values) DropdownMenuItem(value: l, child: Text(l.label)),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _cusLayout = v);
                    unawaited(
                      SharedPreferences.getInstance().then((p) => p.setString(_kCusLayoutPrefKey, v.name)),
                    );
                  },
          ),
          const SizedBox(height: 4),
          Text('One venue in scope always exports its CUS BY EST sheet.', style: hint),
        ],
        const SizedBox(height: 12),
        if (widget.isMobile) ...[
          officer,
          const SizedBox(height: 8),
          mayor,
        ] else
          Row(
            children: [
              Expanded(child: officer),
              const SizedBox(width: 10),
              Expanded(child: mayor),
            ],
          ),
        const SizedBox(height: 4),
        Text('Printed on the CUS BY EST footer and the PDF. Remembered on this device.', style: hint),
      ],
    );
  }

  Widget _buildEntityScopeSection() {
    final hint = widget.isProvincial
        ? 'OPTACA / Governor: pick one spot, all spots in an LGU, or one establishment.'
        : 'LGU: only tourist spots and establishments under your municipality.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Scope (spot / establishment)',
          style: TextStyle(
            color: widget.textDark,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: TextStyle(
            color: widget.textMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        _buildEntityScopeFields(),
      ],
    );
  }

  Widget _buildEntityScopeFields() {
    final allLabel = widget.isProvincial
        ? 'All municipalities (province)'
        : 'All spots & establishments in this LGU';
    final munSpots = _eligibleMunicipalitySpots;
    final munName = _resolvedMunicipalityDisplayName;
    final munFilterRequired =
        _entityKind == DotReportEntityKind.municipalitySpots;
    final showMunFilter = widget.isProvincial &&
        (_entityKind != DotReportEntityKind.all || munFilterRequired);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<DotReportEntityKind>(
          key: ValueKey('fill_for_${_entityKind.name}'),
          initialValue: _entityKind,
          decoration: InputDecoration(
            labelText: 'Fill forms for',
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.primaryColor, width: 1.4),
            ),
          ),
          items: [
            DropdownMenuItem(
              value: DotReportEntityKind.all,
              child: Text(allLabel),
            ),
            const DropdownMenuItem(
              value: DotReportEntityKind.spot,
              child: Text('One tourist spot (VAR / attraction QR)'),
            ),
            DropdownMenuItem(
              value: DotReportEntityKind.municipalitySpots,
              child: Text(
                widget.isProvincial
                    ? 'All tourist spots within selected municipality'
                    : 'All tourist spots in this municipality',
              ),
            ),
            const DropdownMenuItem(
              value: DotReportEntityKind.establishment,
              child: Text('One establishment (DAE / hotel register)'),
            ),
          ],
          onChanged: _busy
              ? null
              : (v) {
                  if (v == null) return;
                  setState(() {
                    _entityKind = v;
                    _selectedEntity = null;
                    _syncFormToScope();
                  });
                  unawaited(_refreshPreview());
                },
        ),
        if (showMunFilter) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('mun_filter_$_entityMunicipalityFilter'),
            initialValue: _entityMunicipalityFilter,
            decoration: InputDecoration(
              labelText: munFilterRequired
                  ? 'Select city / municipality'
                  : 'Filter list by LGU (optional)',
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(
                  munFilterRequired
                      ? 'Select city / municipality'
                      : 'All LGUs',
                ),
              ),
              for (final m in getMisamisOccidentalMunicipalities())
                DropdownMenuItem(value: m.id, child: Text(m.name)),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    setState(() {
                      _entityMunicipalityFilter = v ?? '';
                      _selectedEntity = null;
                    });
                    unawaited(_refreshPreview());
                  },
          ),
        ],
        if (_entityKind == DotReportEntityKind.municipalitySpots) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.primaryColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.primaryColor.withValues(alpha: 0.22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  munName.isEmpty
                      ? 'Select a city or municipality to include all eligible tourist spots.'
                      : 'All eligible tourist spots in $munName will be included in this report.',
                  style: TextStyle(
                    color: widget.textDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  munName.isEmpty
                      ? 'Included tourist spots: —'
                      : 'Included tourist spots: ${munSpots.length}',
                  style: TextStyle(
                    color: widget.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'VAR 2 counts visitor units from QR check-ins (party size / companions). '
                  'Check-in visits and unique tourist accounts are not the same — see the preview summary.',
                  style: TextStyle(
                    color: widget.textMuted,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_entityKind == DotReportEntityKind.spot) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('spot_${_selectedEntity?.id ?? 'none'}_$_entityMunicipalityFilter'),
            initialValue: _selectedEntity?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Tourist spot',
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: [
              for (final s in _spotOptions)
                DropdownMenuItem(
                  value: s.id,
                  child: Text(
                    s.dropdownLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (id) {
                    DotReportEntityOption? match;
                    for (final s in _spotOptions) {
                      if (s.id == id) {
                        match = s;
                        break;
                      }
                    }
                    setState(() => _selectedEntity = match);
                    unawaited(_refreshPreview());
                  },
          ),
          if (_selected.category == DotFormCategory.accommodation || _isCus)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _isCus
                    ? 'Tip: CUS MICE uses venue event logs. Pick “One establishment” for a single venue.'
                    : 'Tip: DAE forms use hotel DOT registers (whole months). Pick “One establishment” for a single hotel.',
                style: TextStyle(color: widget.textMuted, fontSize: 11.5),
              ),
            ),
        ],
        if (_entityKind == DotReportEntityKind.establishment) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedEntity?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Establishment',
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: [
              for (final e in _establishmentOptions)
                DropdownMenuItem(
                  value: e.id,
                  child: Text(
                    e.dropdownLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (id) {
                    DotReportEntityOption? match;
                    for (final e in _establishmentOptions) {
                      if (e.id == id) {
                        match = e;
                        break;
                      }
                    }
                    setState(() => _selectedEntity = match);
                    unawaited(_refreshPreview());
                  },
          ),
          if (_selected.category == DotFormCategory.attraction || _isCus)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _isCus
                    ? 'Only venues with “We host events (MICE)” turned on are listed.'
                    : 'Tip: VAR forms use attraction QR check-ins. Prefer “One tourist spot” for VAR.',
                style: TextStyle(color: widget.textMuted, fontSize: 11.5),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildFormTypeDropdown() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final menuWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 420.0;
        return DropdownMenu<DotFormCatalogEntry>(
          key: ValueKey('${_entityKind.name}:${_selected.id}'),
          controller: _formSearchController,
          initialSelection: _selected,
          enableFilter: true,
          requestFocusOnTap: true,
          width: menuWidth,
          menuHeight: 360,
          leadingIcon: Icon(
            Icons.search_rounded,
            color: widget.primaryColor,
            size: 20,
          ),
          trailingIcon: Icon(
            Icons.arrow_drop_down_rounded,
            color: widget.textMuted,
          ),
          inputDecorationTheme: InputDecorationTheme(
            isDense: true,
            filled: true,
            fillColor: _locked ? Colors.white : const Color(0xFFF8FAFC),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: _locked ? 14 : 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.primaryColor, width: 1.4),
            ),
            hintStyle: TextStyle(color: widget.textMuted, fontSize: 13),
          ),
          textStyle: TextStyle(
            color: widget.textDark,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
          hintText: 'Search form type…',
          filterCallback: (entries, filter) {
            final q = filter.trim();
            if (q.isEmpty || q == _selected.title) return entries;
            return [
              for (final e in entries)
                if (e.value.matchesSearch(q)) e,
            ];
          },
          onSelected: (form) {
            if (form == null || _busy) return;
            _onFormSelected(form);
          },
          dropdownMenuEntries: [
            for (final form in _scopedCatalog)
              DropdownMenuEntry<DotFormCatalogEntry>(
                value: form,
                label: form.title,
                leadingIcon: Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: widget.primaryColor,
                ),
                labelWidget: SizedBox(
                  width: menuWidth - 72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        form.title,
                        style: TextStyle(
                          color: widget.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${form.category.label} · ${form.capabilityLabel}',
                        style: TextStyle(
                          color: widget.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _aeRegisterSourceStrip() {
    final name = widget.lockedEstablishment?.name.trim().isNotEmpty == true
        ? widget.lockedEstablishment!.name.trim()
        : widget.scopeLabel;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          Icon(Icons.hotel_rounded, size: 18, color: widget.primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(color: widget.textDark, fontSize: 12.5, height: 1.3),
                children: [
                  const TextSpan(
                    text: 'Filled from your own register: ',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: widget.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedFormMeta() {
    final badge = _selected.capabilityLabel.trim().isEmpty
        ? 'ATMOS fill'
        : _selected.capabilityLabel.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFDBA74).withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: widget.primaryColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _selected.subtitle,
              style: TextStyle(
                color: widget.textMuted,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilledPreviewSection() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _sectionHeading(
                  icon: Icons.table_chart_rounded,
                  title: 'Filled Data Preview',
                  subtitle: _preview?.summaryLine ??
                      'Rows that will be written into ${_selected.title} (best effort from current data).',
                ),
              ),
              if (_previewLoading)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.primaryColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPreviewTable(),
        ],
      ),
    );
  }

  Widget _buildPreviewTable() {
    final preview = _preview;
    if (_previewLoading && preview == null) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.borderColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: widget.primaryColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Building preview…',
              style: TextStyle(color: widget.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (preview == null || preview.isEmpty) {
      return CustomPaint(
        painter: _DotDashedBorderPainter(
          color: widget.borderColor.withValues(alpha: 0.95),
          radius: 12,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 30),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: widget.primaryColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.insert_chart_outlined_rounded,
                  color: widget.primaryColor.withValues(alpha: 0.9),
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'No check-in records found for the selected report and date range.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Adjust the dates or scope — the preview updates automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(color: widget.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final cellStyle = TextStyle(color: widget.textDark, fontSize: 12.5);
    final footerStyle = TextStyle(
      color: widget.textDark,
      fontWeight: FontWeight.w800,
      fontSize: 12.5,
    );
    Widget text(String value, TextStyle style) => Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

    bool numericHeader(String h) {
      final s = h.toLowerCase();
      return RegExp(r'^\d{4}-\d{2}$').hasMatch(h.trim()) ||
          s.contains('arrival') ||
          s.contains('night') ||
          s.contains('check') ||
          s.contains('guest') ||
          s.contains('room') ||
          s.contains('occupancy') ||
          s.contains('total') ||
          s.contains('value') ||
          s == 'item';
    }

    return AtmosResponsiveTable(
      headerColor: const Color(0xFFFFF1E7),
      headerTextColor: widget.textDark,
      footerColor: const Color(0xFFFFEDD5),
      columns: [
        for (final (i, h) in preview.headers.indexed)
          AtmosTableColumn(
            h,
            flex: i == 0 ? 3 : (h.length > 14 ? 2 : 1),
            minWidth: i == 0
                ? 168
                : (h.length * 7.2).clamp(96, 160).toDouble(),
            align: i == 0 && !numericHeader(h)
                ? Alignment.centerLeft
                : Alignment.center,
          ),
      ],
      rows: [
        for (final row in preview.rows)
          [for (final cell in row) text(cell, cellStyle)],
      ],
      footer: preview.footer == null
          ? null
          : [for (final cell in preview.footer!) text(cell, footerStyle)],
    );
  }

  String get _excelActionLabel {
    if (_excelBusy) return 'Generating Excel...';
    return 'Download Excel';
  }

  String get _pdfActionLabel {
    if (_pdfBusy) return 'Generating PDF...';
    return 'Download PDF';
  }

  ButtonStyle _primaryDownloadStyle({required bool stretch}) {
    return ElevatedButton.styleFrom(
      backgroundColor: widget.primaryColor,
      foregroundColor: Colors.white,
      disabledBackgroundColor: widget.primaryColor.withValues(alpha: 0.55),
      disabledForegroundColor: Colors.white,
      elevation: 0,
      minimumSize: Size(stretch ? double.infinity : 0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return Colors.white.withValues(alpha: 0.10);
        }
        if (states.contains(WidgetState.pressed)) {
          return Colors.white.withValues(alpha: 0.16);
        }
        return null;
      }),
    );
  }

  Widget _downloadBusyIcon() {
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Colors.white,
      ),
    );
  }

  Widget _buildExportControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final stacked = width < 640 || widget.isMobile;
        final wrapTwo = !stacked && width < 980;

        final start = _dateField(
          'Start Date',
          _start,
          (d) => _onDateChanged(d, isStart: true),
        );
        final end = _dateField(
          'End Date',
          _end,
          (d) => _onDateChanged(d, isStart: false),
        );
        final paper = _paperSizeField(expand: true);
        final excelBtn = ElevatedButton.icon(
          // Disable while any export runs; only Excel shows Generating.
          onPressed: _busy ? null : _generateExcel,
          icon: _excelBusy
              ? _downloadBusyIcon()
              : const Icon(Icons.table_view_outlined, size: 18),
          label: Text(_excelActionLabel),
          style: _primaryDownloadStyle(stretch: stacked),
        );
        final pdfBtn = ElevatedButton.icon(
          // Disable while any export runs; only PDF shows Generating.
          onPressed: _busy ? null : _generatePdf,
          icon: _pdfBusy
              ? _downloadBusyIcon()
              : const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text(
            _pdfBusy
                ? _pdfActionLabel
                : '$_pdfActionLabel (${_paperSize.label})',
          ),
          style: _primaryDownloadStyle(stretch: stacked),
        );
        final blank = Align(
          alignment: stacked ? Alignment.center : Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : () => _downloadOfficialBlank(_selected),
            child: Text(
              'Official empty template',
              style: TextStyle(color: widget.textMuted, fontSize: 12),
            ),
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              start,
              const SizedBox(height: 10),
              end,
              const SizedBox(height: 12),
              paper,
              const SizedBox(height: 12),
              excelBtn,
              const SizedBox(height: 8),
              pdfBtn,
              blank,
            ],
          );
        }

        if (wrapTwo) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: start),
                  const SizedBox(width: 12),
                  Expanded(child: end),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(flex: 5, child: paper),
                  const SizedBox(width: 12),
                  Expanded(flex: 4, child: excelBtn),
                  const SizedBox(width: 10),
                  Expanded(flex: 4, child: pdfBtn),
                ],
              ),
              blank,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(flex: 3, child: start),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: end),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: paper),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: excelBtn),
                const SizedBox(width: 10),
                Expanded(flex: 3, child: pdfBtn),
              ],
            ),
            blank,
          ],
        );
      },
    );
  }

  Widget _dateField(
    String label,
    DateTime? value,
    ValueChanged<DateTime> onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: widget.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _busy
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: value ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) onSelect(picked);
                  },
            child: Ink(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value == null
                          ? 'Select date'
                          : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color:
                            value == null ? widget.textMuted : widget.textDark,
                        fontSize: 13,
                        fontWeight: value == null
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.calendar_today_rounded,
                    color: widget.primaryColor,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _resolveCheckInsForExport({
    required DateTime start,
    required DateTime end,
  }) async {
    // Establishment scope: attraction QR rows are not AE stays — leave empty
    // for VAR so preview gaps stay honest when user picks AE + VAR.
    if (_entityKind == DotReportEntityKind.establishment) return const [];
    List<Map<String, dynamic>> base;
    if (widget.isProvincial) {
      base = List<Map<String, dynamic>>.from(widget.checkIns);
      final munFilter = normalizeMunicipalityId(_entityMunicipalityFilter);
      if (munFilter.isNotEmpty &&
          _entityKind != DotReportEntityKind.all) {
        base = DotReportEntityScope.filterCheckInsForMunicipality(
          base,
          municipalityId: munFilter,
        );
      }
    } else {
      final mid = normalizeMunicipalityId(widget.municipalityId);
      if (mid.isEmpty) {
        base = List<Map<String, dynamic>>.from(widget.checkIns);
      } else {
        try {
          final fetched = await LguCheckInReportQuery.fetchRange(
            municipalityQueryIds: municipalityIdsForQuery(mid),
            start: start,
            end: end,
          );
          if (fetched.isEmpty) {
            base = List<Map<String, dynamic>>.from(widget.checkIns);
          } else {
            final byId = <String, Map<String, dynamic>>{
              for (final c in fetched)
                if ((c['id']?.toString() ?? '').isNotEmpty) c['id'].toString(): c,
              for (final c in widget.checkIns)
                if ((c['id']?.toString() ?? '').isNotEmpty) c['id'].toString(): c,
            };
            base = byId.values.toList();
          }
        } catch (e) {
          debugPrint('[DotReportExportPanel] range fetch: $e');
          base = List<Map<String, dynamic>>.from(widget.checkIns);
        }
      }
    }

    if (_entityKind == DotReportEntityKind.spot && _selectedEntity != null) {
      return DotReportEntityScope.filterCheckInsForSpot(
        base,
        spotId: _selectedEntity!.id,
        spotName: _selectedEntity!.name,
      );
    }
    if (_entityKind == DotReportEntityKind.municipalitySpots) {
      final spots = _eligibleMunicipalitySpots;
      if (spots.isEmpty) return const [];
      return DotReportEntityScope.filterCheckInsForSpots(
        base,
        spotIds: [
          for (final s in spots)
            if (s.spotId.trim().isNotEmpty) s.spotId,
        ],
        spotNames: [
          for (final s in spots)
            if (s.name.trim().isNotEmpty) s.name,
        ],
      );
    }
    return base;
  }

  /// Hotel DOT registers for DAE-family forms only (VAR forms skip the query).
  Future<AeRegisterReportData> _resolveAeRegisterForDae({
    required DotFormCatalogEntry form,
    required DateTime start,
    required DateTime end,
  }) async {
    if (form.category != DotFormCategory.accommodation) {
      return AeRegisterReportData.empty;
    }
    // Attraction scopes → VAR only (switch to establishment for hotel data).
    if (_isAttractionScope) {
      return AeRegisterReportData.empty;
    }
    try {
      final oneAe = _entityKind == DotReportEntityKind.establishment && _selectedEntity != null;
      return await fetchAeRegisterReportData(
        startDate: start,
        endDate: end,
        aeId: oneAe ? _selectedEntity!.id : null,
        municipalityId: oneAe
            ? null
            : widget.isProvincial
                ? (normalizeMunicipalityId(_entityMunicipalityFilter).isEmpty
                    ? null
                    : _entityMunicipalityFilter)
                : widget.municipalityId,
        includeRows: form.id == 'dae1a_manual' ||
            form.id == 'dae1b2' ||
            form.id == 'dae1b2_domestic',
      );
    } catch (e) {
      debugPrint('[DotReportExportPanel] AE registers: $e');
      return AeRegisterReportData.empty;
    }
  }
  /// Venue MICE event logs for the CUS form only.
  Future<MiceReportData> _resolveMiceForCus({
    required DotFormCatalogEntry form,
    required DateTime start,
    required DateTime end,
  }) async {
    if (form.reportType != DotReportType.cusMice || _isAttractionScope) {
      return MiceReportData.empty;
    }
    try {
      final oneAe = _entityKind == DotReportEntityKind.establishment && _selectedEntity != null;
      return await fetchMiceReportData(
        startDate: start,
        endDate: end,
        aeId: oneAe ? _selectedEntity!.id : null,
        municipalityId: oneAe
            ? null
            : widget.isProvincial
                ? (normalizeMunicipalityId(_entityMunicipalityFilter).isEmpty ? null : _entityMunicipalityFilter)
                : widget.municipalityId,
        includeDrafts: _miceIncludeDrafts,
        categories: Set.of(_miceCategories),
      );
    } catch (e) {
      debugPrint('[DotReportExportPanel] MICE logs: $e');
      return MiceReportData.empty;
    }
  }

  /// Sign-off subjects (venue-months) behind the selected form's PDF.
  (String, List<({String id, String aeName, int year, int month})>) _signOffSubjects(
    AeRegisterReportData register,
    MiceReportData mice,
  ) {
    if (_isCus) {
      return (
        SignOffSubjects.miceRegister,
        [for (final r in mice.reports) (id: r.id, aeName: r.aeName, year: r.year, month: r.month)],
      );
    }
    return (
      SignOffSubjects.aeRegister,
      [for (final r in register.reports) (id: r.id, aeName: r.aeName, year: r.year, month: r.month)],
    );
  }

  /// Latest establishment sign-off per venue-month for the PDF signature block.
  Future<(List<DotPdfSignOff>, List<String>)> _resolveSignOffsForPdf(
    AeRegisterReportData register,
    MiceReportData mice,
  ) async {
    final (subjectType, reports) = _signOffSubjects(register, mice);
    if (reports.isEmpty) return (const <DotPdfSignOff>[], const <String>[]);
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'];
    try {
      final latest = await SignOffService.latestForSubjects(
        subjectType: subjectType,
        subjectIds: reports.map((r) => r.id),
        ownerId: widget.lockedEstablishment?.id,
      );
      final signed = <DotPdfSignOff>[];
      final unsigned = <String>[];
      for (final r in reports) {
        final label = '${r.aeName.isEmpty ? 'Establishment' : r.aeName} · ${months[r.month - 1]} ${r.year}';
        final s = latest[r.id];
        if (s == null) {
          unsigned.add(label);
          continue;
        }
        signed.add(DotPdfSignOff(
          label: label,
          name: s.signerName,
          position: s.signerPosition,
          action: s.actionLabel,
          signedAt: s.createdAt,
          signaturePng: s.signaturePng,
        ));
      }
      return (signed, unsigned);
    } catch (e) {
      debugPrint('[DotReportExportPanel] sign-offs: $e');
      return (const <DotPdfSignOff>[], const <String>[]);
    }
  }

  /// Returns false and snacks when spot / municipality / AE scope is incomplete.
  bool _scopeReadyForExport() {
    if (_entityKind == DotReportEntityKind.municipalitySpots) {
      if (widget.isProvincial && _resolvedMunicipalityFilter.isEmpty) {
        _snack('Select a city or municipality first', Colors.orange);
        return false;
      }
      return true;
    }
    if (_entityKind != DotReportEntityKind.all && _selectedEntity == null) {
      _snack(
        _entityKind == DotReportEntityKind.spot
            ? 'Select a tourist spot first'
            : 'Select an establishment first',
        Colors.orange,
      );
      return false;
    }
    return true;
  }

  Future<void> _generateExcel() async {
    if (_activeExport != null) return;
    if (_start == null || _end == null) {
      _snack('Please select both start and end dates', Colors.orange);
      return;
    }
    if (_end!.isBefore(_start!)) {
      _snack('End date must be on or after start date', Colors.orange);
      return;
    }
    if (!_scopeReadyForExport()) return;

    setState(() => _activeExport = _DotExportOp.excel);

    try {
      final end =
          DateTime(_end!.year, _end!.month, _end!.day, 23, 59, 59, 999);
      final checkIns = await _resolveCheckInsForExport(
        start: _start!,
        end: end,
      );
      final aeRegister = await _resolveAeRegisterForDae(
        form: _selected,
        start: _start!,
        end: end,
      );
      final mice = await _resolveMiceForCus(form: _selected, start: _start!, end: end);
      if (_isCus) _saveSignatories();
      final result = await _service.exportCatalog(
        form: _selected,
        startDate: _start!,
        endDate: end,
        checkIns: checkIns,
        tourists: widget.tourists,
        catalogSpots: _effectiveCatalog,
        scopeLabel: _effectiveScopeLabel,
        scopeSlug: _effectiveScopeSlug,
        parseTimestamp: widget.parseTimestamp,
        aeRegister: aeRegister,
        mice: mice,
        cusOptions: _cusOptions,
      );
      await downloadXlsxFile(result.filename, result.bytes);
      if (!mounted) return;
      unawaited(_refreshPreview());
      _snack(
        xlsxDownloadUsesShareSheet
            ? 'Excel ready — use the share sheet to save'
            : 'Download started: ${result.filename}',
        widget.primaryColor,
      );
    } on DotReportTemplateFetchException catch (e) {
      if (!mounted) return;
      _snack(e.message, Colors.red.shade700);
    } catch (e) {
      if (!mounted) return;
      _snack('Export failed: $e', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _activeExport = null);
    }
  }

  Future<void> _generatePdf() async {
    if (_activeExport != null) return;
    if (_start == null || _end == null) {
      _snack('Please select both start and end dates', Colors.orange);
      return;
    }
    if (_end!.isBefore(_start!)) {
      _snack('End date must be on or after start date', Colors.orange);
      return;
    }
    if (!_scopeReadyForExport()) return;

    setState(() => _activeExport = _DotExportOp.pdf);
    try {
      final end =
          DateTime(_end!.year, _end!.month, _end!.day, 23, 59, 59, 999);
      final checkIns = await _resolveCheckInsForExport(
        start: _start!,
        end: end,
      );
      final aeRegister = await _resolveAeRegisterForDae(
        form: _selected,
        start: _start!,
        end: end,
      );
      final mice = await _resolveMiceForCus(form: _selected, start: _start!, end: end);
      if (_isCus) _saveSignatories();
      final preview = buildDotReportPreview(
        form: _selected,
        startDate: _start!,
        endDate: end,
        checkIns: checkIns,
        tourists: widget.tourists,
        catalogSpots: _effectiveCatalog,
        scopeLabel: _effectiveScopeLabel,
        parseTimestamp: widget.parseTimestamp,
        aeRegister: aeRegister,
        mice: mice,
      );
      final (signOffs, unsigned) = await _resolveSignOffsForPdf(aeRegister, mice);
      final bytes = await buildDotReportPdfBytes(
        form: _selected,
        preview: preview,
        scopeLabel: _effectiveScopeLabel,
        startDate: _start!,
        endDate: end,
        paperSize: _paperSize,
        signOffs: signOffs,
        unsignedLabels: unsigned,
        signatories: _isCus ? _cusSignatories : const [],
      );
      final filename = dotReportPdfFilename(
        form: _selected,
        scopeSlug: _effectiveScopeSlug,
        startDate: _start!,
        endDate: end,
        paperSize: _paperSize,
      );
      await downloadPdfFile(filename, bytes);
      if (!mounted) return;
      setState(() => _preview = preview);
      _snack(
        pdfDownloadUsesShareSheet
            ? 'PDF ready — use the share sheet to save'
            : 'Download started: $filename',
        widget.primaryColor,
      );
    } catch (e) {
      if (!mounted) return;
      _snack('PDF export failed: $e', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _activeExport = null);
    }
  }

  Future<void> _downloadOfficialBlank(DotFormCatalogEntry form) async {
    if (_activeExport != null) return;
    setState(() => _activeExport = _DotExportOp.blank);
    try {
      final bytes = await _service.downloadCatalogBlank(form);
      await downloadXlsxFile(form.objectFilename, bytes);
      if (!mounted) return;
      _snack(
        xlsxDownloadUsesShareSheet
            ? 'Empty official template ready — share sheet to save'
            : 'Empty template download started: ${form.objectFilename}',
        widget.textMuted,
      );
    } on DotReportTemplateFetchException catch (e) {
      if (!mounted) return;
      _snack(e.message, Colors.red.shade700);
    } catch (e) {
      if (!mounted) return;
      _snack('Download failed: $e', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _activeExport = null);
    }
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

class _DotPanelWavePainter extends CustomPainter {
  const _DotPanelWavePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, size.height * 0.55)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.15,
        size.width * 0.55,
        size.height * 0.48,
      )
      ..quadraticBezierTo(
        size.width * 0.8,
        size.height * 0.82,
        size.width,
        size.height * 0.4,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DotPanelWavePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DotDashedBorderPainter extends CustomPainter {
  const _DotDashedBorderPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth > metric.length
            ? metric.length
            : distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotDashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
