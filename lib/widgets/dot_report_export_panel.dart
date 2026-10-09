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

  @override
  State<DotReportExportPanel> createState() => _DotReportExportPanelState();
}

class _DotReportExportPanelState extends State<DotReportExportPanel> {
  final _service = DotReportExportService();
  final _formSearchController = TextEditingController();
  late DotFormCatalogEntry _selected;
  DateTime? _start;
  DateTime? _end;
  bool _busy = false;
  static const _kPaperPrefKey = 'dot_report_pdf_paper_size';
  DotPdfPaperSize _paperSize = DotPdfPaperSize.a4;
  String? _lastGapsPreview;
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
          'PDF paper size',
          style: TextStyle(
            fontSize: 12,
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

  List<DotReportEntityOption> get _spotOptions {
    final munFilter = normalizeMunicipalityId(_entityMunicipalityFilter);
    final out = <DotReportEntityOption>[];
    for (final s in widget.catalogSpots) {
      if (s.spotId.trim().isEmpty && s.name.trim().isEmpty) continue;
      // Catalog may not carry municipality — LGU catalog is already scoped.
      out.add(
        DotReportEntityOption(
          id: s.spotId.trim().isNotEmpty ? s.spotId.trim() : s.name.trim(),
          name: s.name.trim().isEmpty ? s.spotId : s.name.trim(),
          kind: DotReportEntityKind.spot,
          municipalityId: widget.isProvincial ? '' : (widget.municipalityId ?? ''),
          municipalityName: widget.isProvincial ? '' : widget.scopeLabel,
        ),
      );
    }
    // Provincial spot maps often include municipality on raw governor spots —
    // catalog from governor/optaca may lack mid; mun filter only applies when
    // we later enrich. For now filter is no-op unless we pass mid on catalog.
    if (widget.isProvincial && munFilter.isNotEmpty) {
      // Keep all spots if catalog has no municipality metadata.
      return out;
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
      );

  String get _effectiveScopeSlug => DotReportEntityScope.slugFor(
        baseSlug: widget.scopeSlug,
        kind: _entityKind,
        entityId: _selectedEntity?.id,
      );

  List<DotVar2SpotCatalogEntry> get _effectiveCatalog {
    if (_entityKind != DotReportEntityKind.spot || _selectedEntity == null) {
      return widget.catalogSpots;
    }
    final id = _selectedEntity!.id.toLowerCase();
    final name = _selectedEntity!.name.toLowerCase();
    final matched = [
      for (final s in widget.catalogSpots)
        if (s.spotId.trim().toLowerCase() == id ||
            s.name.trim().toLowerCase() == name)
          s,
    ];
    if (matched.isNotEmpty) return matched;
    return [
      DotVar2SpotCatalogEntry(
        spotId: _selectedEntity!.id,
        name: _selectedEntity!.name,
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
      _selected = form;
      _formSearchController.text = form.title;
      _lastGapsPreview = null;
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

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(widget.isMobile ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: body,
    );
  }

  Widget _buildBody() {
    final scopeHint = widget.isProvincial
        ? 'Province-wide best-effort fill: preview every form, then download Excel or PDF. Gaps update as data grows.'
        : 'Search any DOT / DAE / MICE form — preview filled data (with gaps), then download Excel or PDF.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.isProvincial
              ? 'DOT templates (province-wide)'
              : 'Official forms',
          style: TextStyle(
            color: widget.textDark,
            fontSize: widget.isProvincial ? 14.5 : 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          scopeHint,
          style: TextStyle(
            color: widget.textMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Form type',
          style: TextStyle(
            color: widget.textDark,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _buildFormTypeDropdown(),
        const SizedBox(height: 10),
        _buildSelectedFormMeta(),
        const SizedBox(height: 14),
        if (_locked)
          Text(
            'Filled from your own register: ${widget.lockedEstablishment!.name}',
            style: TextStyle(color: widget.textMuted, fontSize: 12),
          )
        else
          _buildEntityScopeSection(),
        if (_isCus) ...[
          const SizedBox(height: 14),
          _buildCusOptions(),
        ],
        const SizedBox(height: 14),
        Text(
          'Custom date range',
          style: TextStyle(
            color: widget.textDark,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        widget.isMobile ? _buildControlsStacked() : _buildControlsRow(),
        const SizedBox(height: 16),
        _buildFilledPreviewSection(),
        if (_preview != null && _preview!.gaps.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildLiveGapsCard(_preview!.gaps),
        ],
        if (_lastGapsPreview != null) ...[
          const SizedBox(height: 12),
          _buildGapsPreview(),
        ],
      ],
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
    final allLabel = widget.isProvincial
        ? 'All municipalities (province)'
        : 'All spots & establishments in this LGU';
    final hint = widget.isProvincial
        ? 'OPTACA / Governor: pick any spot or establishment in Misamis Occidental.'
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
        DropdownButtonFormField<DotReportEntityKind>(
          initialValue: _entityKind,
          decoration: InputDecoration(
            labelText: 'Fill forms for',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                  });
                  unawaited(_refreshPreview());
                },
        ),
        if (widget.isProvincial &&
            _entityKind != DotReportEntityKind.all) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _entityMunicipalityFilter,
            decoration: InputDecoration(
              labelText: 'Filter list by LGU (optional)',
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('All LGUs')),
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
        if (_entityKind == DotReportEntityKind.spot) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
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
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
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
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          hintText: 'Search form type…',
          filterCallback: (entries, filter) {
            final q = filter.trim();
            if (q.isEmpty) return entries;
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
            for (final form in _catalog)
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

  Widget _buildSelectedFormMeta() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.primaryColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.primaryColor.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.primaryColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _selected.capabilityLabel,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Filled data preview',
                style: TextStyle(
                  color: widget.textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_previewLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.primaryColor,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _preview?.summaryLine ??
              'Rows that will be written into ${_selected.title} (best effort from current data).',
          style: TextStyle(
            color: widget.textMuted,
            fontSize: 11.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        _buildPreviewTable(),
      ],
    );
  }

  Widget _buildLiveGapsCard(List<String> gaps) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ATMOS gaps (will fill as fields / hotel registers arrive)',
            style: TextStyle(
              color: widget.textDark,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final g in gaps.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $g',
                style: TextStyle(
                  color: widget.textMuted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ),
          if (gaps.length > 6)
            Text(
              '• …and ${gaps.length - 6} more',
              style: TextStyle(color: widget.textMuted, fontSize: 11),
            ),
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
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.borderColor),
        ),
        child: Text(
          'Building preview…',
          style: TextStyle(color: widget.textMuted, fontSize: 13),
        ),
      );
    }
    if (preview == null || preview.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.borderColor),
        ),
        child: Column(
          children: [
            Icon(Icons.table_chart_outlined, color: widget.textMuted, size: 28),
            const SizedBox(height: 8),
            Text(
              'No check-in rows for this form and date range',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.textDark,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Adjust the dates or seed visits, then preview updates automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(color: widget.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final borderSide = BorderSide(color: widget.borderColor);
    final headerStyle = TextStyle(
      color: widget.textDark,
      fontWeight: FontWeight.w800,
      fontSize: 11.5,
      letterSpacing: 0.2,
    );
    final cellStyle = TextStyle(
      color: widget.textDark,
      fontSize: 12.5,
    );
    final footerStyle = TextStyle(
      color: widget.textDark,
      fontWeight: FontWeight.w800,
      fontSize: 12.5,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : 640.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minW),
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(Color(0xFFF1F5F9)),
                headingRowHeight: 44,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 56,
                horizontalMargin: 14,
                columnSpacing: 18,
                dividerThickness: 1,
                border: TableBorder(
                  top: borderSide,
                  bottom: borderSide,
                  left: borderSide,
                  right: borderSide,
                  horizontalInside: borderSide,
                  verticalInside: borderSide,
                ),
                headingTextStyle: headerStyle,
                dataTextStyle: cellStyle,
                columns: [
                  for (final h in preview.headers)
                    DataColumn(label: Text(h)),
                ],
                rows: [
                  for (var i = 0; i < preview.rows.length; i++)
                    DataRow(
                      color: WidgetStatePropertyAll(
                        i.isOdd ? const Color(0xFFF8FAFC) : Colors.white,
                      ),
                      cells: [
                        for (final cell in preview.rows[i])
                          DataCell(Text(cell)),
                      ],
                    ),
                  if (preview.footer != null)
                    DataRow(
                      color: const WidgetStatePropertyAll(Color(0xFFFFF7ED)),
                      cells: [
                        for (final cell in preview.footer!)
                          DataCell(
                            Text(cell, style: footerStyle),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGapsPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.primaryColor.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        _lastGapsPreview!,
        style: TextStyle(
          color: widget.textDark,
          fontSize: 11.5,
          height: 1.4,
        ),
      ),
    );
  }

  String get _excelActionLabel {
    if (_busy) return 'Generating…';
    return 'Download Excel';
  }

  Widget _buildControlsRow() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: 180,
          child: _dateField(
            'Start',
            _start,
            (d) => _onDateChanged(d, isStart: true),
          ),
        ),
        SizedBox(
          width: 180,
          child: _dateField(
            'End',
            _end,
            (d) => _onDateChanged(d, isStart: false),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _busy ? null : _generateExcel,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.table_view_outlined, size: 18),
          label: Text(_excelActionLabel),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        SizedBox(width: 210, child: _paperSizeField(expand: true)),
        OutlinedButton.icon(
          onPressed: _busy ? null : _generatePdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text('Download PDF (${_paperSize.label})'),
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.primaryColor,
            side: BorderSide(color: widget.primaryColor.withValues(alpha: 0.55)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : () => _downloadOfficialBlank(_selected),
          child: Text(
            'Official empty template',
            style: TextStyle(color: widget.textMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildControlsStacked() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dateField('Start', _start, (d) => _onDateChanged(d, isStart: true)),
        const SizedBox(height: 10),
        _dateField('End', _end, (d) => _onDateChanged(d, isStart: false)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _busy ? null : _generateExcel,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.table_view_outlined, size: 18),
          label: Text(_excelActionLabel),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _paperSizeField(expand: true),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _generatePdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text('Download PDF (${_paperSize.label})'),
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.primaryColor,
            side: BorderSide(color: widget.primaryColor.withValues(alpha: 0.55)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : () => _downloadOfficialBlank(_selected),
          child: Text(
            'Official empty template',
            style: TextStyle(color: widget.textMuted, fontSize: 12),
          ),
        ),
      ],
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
        Text(label, style: TextStyle(color: widget.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        InkWell(
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      color: value == null ? widget.textMuted : widget.textDark,
                      fontSize: 13,
                      fontWeight:
                          value == null ? FontWeight.normal : FontWeight.w600,
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
    // Spot scope → attraction only (switch to establishment for hotel data).
    if (_entityKind == DotReportEntityKind.spot) {
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
        includeRows: form.id == 'dae1a_manual',
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
    if (form.reportType != DotReportType.cusMice || _entityKind == DotReportEntityKind.spot) {
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

  Future<void> _generateExcel() async {
    if (_start == null || _end == null) {
      _snack('Please select both start and end dates', Colors.orange);
      return;
    }
    if (_end!.isBefore(_start!)) {
      _snack('End date must be on or after start date', Colors.orange);
      return;
    }
    if (_entityKind != DotReportEntityKind.all && _selectedEntity == null) {
      _snack(
        _entityKind == DotReportEntityKind.spot
            ? 'Select a tourist spot first'
            : 'Select an establishment first',
        Colors.orange,
      );
      return;
    }

    setState(() {
      _busy = true;
      _lastGapsPreview = null;
    });

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
      setState(() {
        _lastGapsPreview =
            '${result.summary}\nGaps noted in ATMOS_GAPS sheet (${result.gaps.length}):\n• ${result.gaps.take(3).join('\n• ')}'
            '${result.gaps.length > 3 ? '\n• …' : ''}';
      });
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generatePdf() async {
    if (_start == null || _end == null) {
      _snack('Please select both start and end dates', Colors.orange);
      return;
    }
    if (_end!.isBefore(_start!)) {
      _snack('End date must be on or after start date', Colors.orange);
      return;
    }
    if (_entityKind != DotReportEntityKind.all && _selectedEntity == null) {
      _snack(
        _entityKind == DotReportEntityKind.spot
            ? 'Select a tourist spot first'
            : 'Select an establishment first',
        Colors.orange,
      );
      return;
    }

    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadOfficialBlank(DotFormCatalogEntry form) async {
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
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
