import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'data.dart';
import 'firestore_loader.dart';
import 'hub_spot_transport_fare_matrix.dart';
import 'hub_spot_transport_fee.dart';
import 'hub_spot_transport_fees_loader.dart';
import 'municipality_bus_terminals.dart';
import 'transportation_fee.dart';
import 'transportation_fees_loader.dart';
import 'services/auth_role_claims.dart';
import 'trip_route_fare_service.dart';

/// Admin view: inter-LGU transportation fees + hub → tourist spot (portal tables).
class AdminMatrixFaresTab extends StatefulWidget {
  const AdminMatrixFaresTab({super.key});

  @override
  State<AdminMatrixFaresTab> createState() => _AdminMatrixFaresTabState();
}

class _AdminMatrixFaresTabState extends State<AdminMatrixFaresTab> {
  bool _loading = true;
  String? _syncNote;
  String _query = '';
  String _queryDebounced = '';
  String? _savingDocId;
  Timer? _searchDebounce;
  late final TextEditingController _searchController;

  List<TransportationFee> _filteredInter = const [];
  List<HubSpotTransportFee> _filteredHub = const [];

  static const _accent = Color(0xFFFF6B00);
  static const _tableBorder = Color(0xFF1C1C1C);
  static const _kTableMaxBodyHeight = 480.0;
  static const _kRowHeight = 34.0;
  static const _kTableRightGutter = 8.0;
  static const _interColW = [150.0, 150.0, 72.0, 84.0, 180.0, 88.0, 80.0];
  static const _hubColW = [140.0, 170.0, 170.0, 68.0, 68.0, 68.0, 80.0];
  final Set<String> _removedHubFallbackIds = {};
  static const _cellStyle = TextStyle(
    fontSize: 12,
    height: 1.15,
    color: AppColors.textDark,
  );

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    SchedulerBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Shows embedded matrix immediately; syncs Firestore in the background.
  Future<void> _bootstrap() async {
    seedTransportationFeesFromEmbeddedMatrixIfEmpty();
    _rebuildFilteredLists();
    if (mounted) {
      setState(() => _loading = false);
    }
    if (hubSpotTransportFeesByDocId.isEmpty) {
      unawaited(_loadHubMatrixFallback());
    }
    unawaited(_syncFromFirestoreQuietly());
  }

  Future<void> _syncFromFirestoreQuietly() async {
    try {
      await loadTransportationFeesFromFirestore();
      if (hubSpotTransportFeesByDocId.isEmpty) {
        await loadHubSpotTransportFeesFromFirestore();
      }
      if (!mounted) return;
      _rebuildFilteredLists();
      setState(() => _syncNote = null);
    } catch (e, st) {
      debugPrint('Matrix fares Firestore sync: $e\n$st');
      seedTransportationFeesFromEmbeddedMatrixIfEmpty();
      if (!mounted) return;
      _rebuildFilteredLists();
      setState(() => _syncNote = _friendlyFirestoreMessage(e));
    }
  }

  Future<void> _load({bool force = false}) async {
    if (!force && transportationFeesByDocId.isNotEmpty) {
      _rebuildFilteredLists();
      if (mounted) setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _syncNote = null;
    });
    seedTransportationFeesFromEmbeddedMatrixIfEmpty();
    try {
      await loadTransportationFeesFromFirestore();
      if (force || hubSpotTransportFeesByDocId.isEmpty) {
        await loadHubSpotTransportFeesFromFirestore();
      }
      if (!mounted) return;
      _rebuildFilteredLists();
      setState(() => _loading = false);
    } catch (e, st) {
      debugPrint('Matrix fares refresh: $e\n$st');
      seedTransportationFeesFromEmbeddedMatrixIfEmpty();
      if (!mounted) return;
      _rebuildFilteredLists();
      setState(() {
        _loading = false;
        _syncNote = _friendlyFirestoreMessage(e);
      });
    }
  }

  static String _friendlyFirestoreMessage(Object error) {
    final s = error.toString();
    if (s.contains('permission-denied')) {
      return 'Could not sync fares from Firestore (permission denied). '
          'Showing embedded matrix — pull down to retry after rules deploy.';
    }
    if (s.contains('INTERNAL ASSERTION FAILED')) {
      return 'Firestore sync paused (browser SDK issue). '
          'Showing embedded fares — do a full page refresh if sync keeps failing.';
    }
    return 'Could not sync fares from Firestore. '
        'Showing embedded matrix — pull down to retry.';
  }

  void _rebuildFilteredLists() {
    final q = _queryDebounced.trim().toLowerCase();

    final inter = transportationFeesByDocId.values.toList()
      ..sort((a, b) {
        final c = a.fromMunicipality.compareTo(b.fromMunicipality);
        if (c != 0) return c;
        return a.toMunicipality.compareTo(b.toMunicipality);
      });

    var hub = hubSpotTransportFeesByDocId.values
        .where((f) => f.direction == HubSpotLegDirection.hubToSpot)
        .toList();
    if (hub.isEmpty && _hubMatrixFallback != null) {
      hub = _hubMatrixFallback!
          .where((f) => !_removedHubFallbackIds.contains(f.id))
          .toList();
    } else if (hub.isEmpty && !_hubMatrixLoading) {
      unawaited(_loadHubMatrixFallback());
    }
    hub.sort((a, b) {
      final c = a.municipality.compareTo(b.municipality);
      if (c != 0) return c;
      return a.toTouristSpotName.compareTo(b.toTouristSpotName);
    });

    if (q.isEmpty) {
      _filteredInter = inter;
      _filteredHub = hub;
      return;
    }

    _filteredInter = inter
        .where(
          (f) =>
              '${f.fromMunicipality} ${f.toMunicipality} ${f.endpointName}'
                  .toLowerCase()
                  .contains(q),
        )
        .toList();
    _filteredHub = hub
        .where(
          (f) =>
              '${f.municipality} ${f.toTouristSpotName} ${f.fromEndpointName}'
                  .toLowerCase()
                  .contains(q),
        )
        .toList();
  }

  void _onSearchChanged(String value) {
    _query = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _queryDebounced = _query;
      _rebuildFilteredLists();
      setState(() {});
    });
  }

  List<HubSpotTransportFee>? _hubMatrixFallback;
  bool _hubMatrixLoading = false;

  Future<void> _loadHubMatrixFallback() async {
    if (_hubMatrixLoading || hubSpotTransportFeesByDocId.isNotEmpty) return;
    _hubMatrixLoading = true;
    final built = await Future<List<HubSpotTransportFee>>(
      buildHubSpotTransportFeesFromMatrix,
    );
    _hubMatrixFallback = built
        .where((f) => f.direction == HubSpotLegDirection.hubToSpot)
        .toList();
    _hubMatrixLoading = false;
    _rebuildFilteredLists();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _accent),
      );
    }

    final inter = _filteredInter;
    final hubToSpot = _filteredHub;

    return RefreshIndicator(
      color: _accent,
      onRefresh: () => _load(force: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_syncNote != null) ...[
              Material(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _syncNote!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Material(
              elevation: 2,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(22),
              color: Colors.white,
              child: TextField(
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search municipality, route, or spot…',
                  hintStyle: TextStyle(
                    color: AppColors.textGrey.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppColors.textGrey.withValues(alpha: 0.85),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 10,
                  ),
                ),
                controller: _searchController,
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Add, edit, or delete fares. Changes save to Firestore (admin/staff only).',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textGrey.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 12),
            _sectionHeader(
              title: 'Transportation fees (between municipalities)',
              count: inter.length,
              addLabel: 'Add route',
              onAdd: _savingDocId == null ? _createInterLguFee : null,
            ),
            const SizedBox(height: 8),
            if (inter.isEmpty)
              _emptyHint(
                transportationFeesByDocId.isEmpty
                    ? 'No inter-LGU fares loaded.'
                    : 'No routes match your search.',
              )
            else
              _virtualizedTable(
                colWidths: _interColW,
                headerLabels: const [
                  'From',
                  'To',
                  'Fare',
                  'Hub type',
                  'Ends at',
                  'Distance',
                  '',
                ],
                expandColumnIndex: 4,
                rowCount: inter.length,
                rowBuilder: (context, index, widths) =>
                    _interLguListRow(inter[index], widths),
              ),
            const SizedBox(height: 20),
            _sectionHeader(
              title: 'Hub → tourist spot',
              count: hubToSpot.length,
              addLabel: 'Add fare',
              onAdd: _savingDocId == null ? _createHubSpotFee : null,
            ),
            const SizedBox(height: 8),
            if (hubToSpot.isEmpty)
              _emptyHint('No hub → tourist spot fares found.')
            else
              _virtualizedTable(
                colWidths: _hubColW,
                headerLabels: const [
                  'Municipality',
                  'Tourist spot',
                  'Bus hub',
                  'Min',
                  'Max',
                  'Fare',
                  '',
                ],
                expandColumnIndex: 2,
                rowCount: hubToSpot.length,
                rowBuilder: (context, index, widths) =>
                    _hubSpotListRow(hubToSpot[index], widths),
              ),
          ],
        ),
      ),
    );
  }

  List<double> _layoutColWidths(
    List<double> base,
    double viewportWidth,
    int expandIndex,
  ) {
    final minTableWidth =
        base.fold(0.0, (sum, w) => sum + w) + _kTableRightGutter;
    if (!viewportWidth.isFinite || viewportWidth <= minTableWidth) {
      return List<double>.from(base);
    }
    final result = List<double>.from(base);
    if (expandIndex >= 0 && expandIndex < result.length) {
      result[expandIndex] += viewportWidth - minTableWidth;
    }
    return result;
  }

  double _tableWidthFor(List<double> colWidths) =>
      colWidths.fold(0.0, (sum, w) => sum + w) + _kTableRightGutter;

  Widget _virtualizedTable({
    required List<double> colWidths,
    required List<String> headerLabels,
    required int expandColumnIndex,
    required int rowCount,
    required Widget Function(BuildContext context, int index, List<double> widths)
        rowBuilder,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _tableWidthFor(colWidths);
        final layoutWidths =
            _layoutColWidths(colWidths, available, expandColumnIndex);
        final tableWidth = _tableWidthFor(layoutWidths);
        final needsHorizontalScroll = tableWidth > available + 0.5;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _tableBorder.withValues(alpha: 0.85),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: SizedBox(
            height: _kTableMaxBodyHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: needsHorizontalScroll
                  ? const AlwaysScrollableScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: needsHorizontalScroll ? tableWidth : available,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _headerRow(headerLabels, layoutWidths),
                    Expanded(
                      child: ListView.builder(
                        primary: false,
                        itemCount: rowCount,
                        itemExtent: _kRowHeight,
                        itemBuilder: (context, index) =>
                            rowBuilder(context, index, layoutWidths),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _headerRow(List<String> labels, List<double> widths) {
    return Container(
      height: _kRowHeight,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            SizedBox(
              width: widths[i],
              child: _th(labels[i]),
            ),
          const SizedBox(width: _kTableRightGutter),
        ],
      ),
    );
  }

  Widget _dataRow(List<Widget> cells, List<double> widths) {
    return Container(
      height: _kRowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            SizedBox(
              width: widths[i],
              child: i == cells.length - 1 ? _tdAction(cells[i]) : _td(cells[i]),
            ),
          const SizedBox(width: _kTableRightGutter),
        ],
      ),
    );
  }

  Widget _interLguListRow(TransportationFee f, List<double> widths) {
    final hubKind = f.endpointType == 'terminal' ? 'Terminal' : 'Bus stop';
    final km = f.estimatedDistance > 0
        ? '~${f.estimatedDistance.toStringAsFixed(1)} km'
        : '—';
    return _dataRow(
      [
        _ellipsis(
          f.fromMunicipality,
          style: _cellStyle.copyWith(fontWeight: FontWeight.w600),
        ),
        _ellipsis(
          f.toMunicipality,
          style: _cellStyle.copyWith(
            color: _accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        _ellipsis(
          formatFarePhp(f.fare),
          style: _cellStyle.copyWith(
            color: _accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        _ellipsis(hubKind),
        _ellipsis(
          f.endpointName,
          style: _cellStyle.copyWith(color: AppColors.textGrey),
        ),
        _ellipsis(km),
        _rowActions(
          enabled: _savingDocId == null,
          loading: _savingDocId == f.id,
          onEdit: () => _editInterLguFee(f),
          onDelete: () => _deleteInterLguFee(f),
        ),
      ],
      widths,
    );
  }

  Widget _hubSpotListRow(HubSpotTransportFee f, List<double> widths) {
    return _dataRow(
      [
        _ellipsis(
          f.municipality,
          style: _cellStyle.copyWith(fontWeight: FontWeight.w600),
        ),
        _ellipsis(
          f.toTouristSpotName,
          style: _cellStyle.copyWith(
            color: _accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        _ellipsis(
          f.fromEndpointName,
          style: _cellStyle.copyWith(color: AppColors.textGrey),
        ),
        _ellipsis(formatFarePhp(f.fareMin)),
        _ellipsis(formatFarePhp(f.fareMax)),
        _ellipsis(
          formatFarePhp(f.fare),
          style: _cellStyle.copyWith(
            color: _accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        _rowActions(
          enabled: _savingDocId == null,
          loading: _savingDocId == f.id,
          onEdit: () => _editHubSpotFee(f),
          onDelete: () => _deleteHubSpotFee(f),
        ),
      ],
      widths,
    );
  }

  Widget _rowActions({
    required bool enabled,
    required bool loading,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit',
          onPressed: enabled ? onEdit : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(
            Icons.edit_outlined,
            size: 18,
            color: _accent.withValues(alpha: enabled ? 1 : 0.4),
          ),
        ),
        IconButton(
          tooltip: 'Delete',
          onPressed: enabled ? onDelete : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(
            Icons.delete_outline,
            size: 18,
            color: Colors.red.shade400.withValues(alpha: enabled ? 1 : 0.4),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader({
    required String title,
    required int count,
    required String addLabel,
    required VoidCallback? onAdd,
  }) {
    return Row(
      children: [
        Expanded(child: _sectionTitle(title, count: count)),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(addLabel),
          style: TextButton.styleFrom(
            foregroundColor: _accent,
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<bool> _confirmDelete(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _persistFee(
    Future<void> Function() save,
    String successMessage,
  ) async {
    try {
      await refreshAuthRoleClaims();
      await save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage), backgroundColor: _accent),
      );
      setState(_rebuildFilteredLists);
    } catch (e) {
      if (!mounted) return;
      final denied = e.toString().contains('permission-denied');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? 'Denied. Sign in as admin/staff, then try again.'
                : 'Could not save: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Municipality? _municipalityByName(String name) {
    for (final m in sortedMunicipalities) {
      if (m.name == name) return m;
    }
    return null;
  }

  List<TouristSpot> _spotsForMunicipality(String municipalityName) {
    return allSpots
        .where((s) => s.location.trim() == municipalityName.trim())
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _createInterLguFee() async {
    applyDefaultMunicipalityBusTerminals();
    final names = sortedMunicipalities.map((m) => m.name).toList();
    if (names.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load municipalities before adding routes.')),
      );
      return;
    }

    var fromName = names.first;
    var toName = names.length > 1 ? names[1] : names.first;
    final fareCtrl = TextEditingController();
    final distCtrl = TextEditingController();
    final endpointCtrl = TextEditingController();
    var endpointType = 'terminal';
    final formKey = GlobalKey<FormState>();

    TransportationFee? created;
    try {
      created = await showDialog<TransportationFee>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) {
            void syncEndpointDefault() {
              final toMuni = _municipalityByName(toName);
              if (toMuni != null && endpointCtrl.text.trim().isEmpty) {
                endpointCtrl.text = transportEndpointFor(toMuni).name;
                endpointType = transportEndpointFor(toMuni).kind;
              }
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              title: const Text('Add municipality route'),
              content: SizedBox(
                width: math.min(440, MediaQuery.sizeOf(ctx).width - 40),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _municipalityDropdown(
                          label: 'From municipality',
                          value: fromName,
                          names: names,
                          onChanged: (v) {
                            if (v == null) return;
                            setDialog(() => fromName = v);
                          },
                        ),
                        const SizedBox(height: 10),
                        _municipalityDropdown(
                          label: 'To municipality',
                          value: toName,
                          names: names,
                          onChanged: (v) {
                            if (v == null) return;
                            setDialog(() {
                              toName = v;
                              syncEndpointDefault();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        _dialogField(
                          controller: fareCtrl,
                          label: 'Fare (₱)',
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = _parsePhpInt(v ?? '');
                            if (n == null || n < 0) return 'Enter a valid fare';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _hubTypeSegmentedControl(
                          endpointType: endpointType,
                          onChanged: (v) => setDialog(() => endpointType = v),
                        ),
                        const SizedBox(height: 12),
                        _dialogField(
                          controller: endpointCtrl,
                          label: 'Ends at (hub name)',
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _dialogField(
                          controller: distCtrl,
                          label: 'Distance (km)',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            final n = _parseKm(v ?? '');
                            if (n == null || n < 0) {
                              return 'Enter a valid distance';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;
                    if (fromName == toName) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('From and To must be different'),
                        ),
                      );
                      return;
                    }
                    final id = transportationFeeDocId(fromName, toName);
                    if (transportationFeesByDocId.containsKey(id)) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('This route already exists'),
                        ),
                      );
                      return;
                    }
                    final dist = _parseKm(distCtrl.text) ?? 0;
                    Navigator.pop(
                      ctx,
                      TransportationFee(
                        id: id,
                        fromMunicipality: fromName,
                        toMunicipality: toName,
                        fromMunicipalitySlug: municipalitySlug(fromName),
                        toMunicipalitySlug: municipalitySlug(toName),
                        fare: _parsePhpInt(fareCtrl.text)!,
                        endpointType: endpointType,
                        endpointName: endpointCtrl.text.trim(),
                        routeType: routeTypeForEstimatedDistanceKm(dist),
                        estimatedDistance: dist,
                      ),
                    );
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      fareCtrl.dispose();
      distCtrl.dispose();
      endpointCtrl.dispose();
    }

    if (created == null || !mounted) return;
    setState(() => _savingDocId = created!.id);
    await _persistFee(
      () => saveTransportationFeeToFirestore(created!),
      'Added ${created.fromMunicipality} → ${created.toMunicipality}',
    );
    if (mounted) setState(() => _savingDocId = null);
  }

  Future<void> _deleteInterLguFee(TransportationFee fee) async {
    final ok = await _confirmDelete(
      'Delete route?',
      'Remove fare for ${fee.fromMunicipality} → ${fee.toMunicipality}?',
    );
    if (!ok || !mounted) return;
    setState(() => _savingDocId = fee.id);
    try {
      await refreshAuthRoleClaims();
      await deleteTransportationFeeFromFirestore(fee.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted ${fee.fromMunicipality} → ${fee.toMunicipality}'),
          backgroundColor: _accent,
        ),
      );
      setState(_rebuildFilteredLists);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingDocId = null);
    }
  }

  Future<void> _createHubSpotFee() async {
    applyDefaultMunicipalityBusTerminals();
    final muniNames = sortedMunicipalities.map((m) => m.name).toList();
    if (muniNames.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Load municipalities before adding fares.')),
      );
      return;
    }

    var muniName = muniNames.first;
    var spots = _spotsForMunicipality(muniName);
    TouristSpot? selectedSpot = spots.isNotEmpty ? spots.first : null;
    final minCtrl = TextEditingController();
    final maxCtrl = TextEditingController();
    final fareCtrl = TextEditingController();
    final hubCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    HubSpotTransportFee? created;
    try {
      created = await showDialog<HubSpotTransportFee>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) {
            final muni = _municipalityByName(muniName);
            if (muni != null && hubCtrl.text.trim().isEmpty) {
              hubCtrl.text = transportEndpointFor(muni).name;
            }
            spots = _spotsForMunicipality(muniName);
            if (selectedSpot != null &&
                !spots.any((s) => s.name == selectedSpot!.name)) {
              selectedSpot = spots.isNotEmpty ? spots.first : null;
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              title: const Text('Add hub → spot fare'),
              content: SizedBox(
                width: math.min(440, MediaQuery.sizeOf(ctx).width - 40),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _municipalityDropdown(
                          label: 'Municipality',
                          value: muniName,
                          names: muniNames,
                          onChanged: (v) {
                            if (v == null) return;
                            setDialog(() {
                              muniName = v;
                              hubCtrl.clear();
                              selectedSpot = null;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        if (spots.isEmpty)
                          Text(
                            'No tourist spots in this municipality. Add a spot first.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade700,
                            ),
                          )
                        else
                          DropdownButtonFormField<TouristSpot>(
                            value: selectedSpot,
                            decoration: _dropdownDecoration('Tourist spot'),
                            items: spots
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      s.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setDialog(() => selectedSpot = v),
                            validator: (v) =>
                                v == null ? 'Select a tourist spot' : null,
                          ),
                        const SizedBox(height: 12),
                        _dialogField(
                          controller: hubCtrl,
                          label: 'Bus hub',
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _dialogField(
                                controller: minCtrl,
                                label: 'Min (₱)',
                                keyboardType: TextInputType.number,
                                validator: (v) {
                                  final n = _parsePhpInt(v ?? '');
                                  if (n == null || n < 0) return 'Invalid';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _dialogField(
                                controller: maxCtrl,
                                label: 'Max (₱)',
                                keyboardType: TextInputType.number,
                                validator: (v) {
                                  final n = _parsePhpInt(v ?? '');
                                  if (n == null || n < 0) return 'Invalid';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _dialogField(
                          controller: fareCtrl,
                          label: 'Fare used (₱)',
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = _parsePhpInt(v ?? '');
                            if (n == null || n < 0) return 'Enter a valid fare';
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;
                    final spot = selectedSpot;
                    final muni = _municipalityByName(muniName);
                    if (spot == null || muni == null) return;
                    final min = _parsePhpInt(minCtrl.text)!;
                    final max = _parsePhpInt(maxCtrl.text)!;
                    final fareValue = _parsePhpInt(fareCtrl.text)!;
                    if (min > max) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Min fare cannot exceed max fare'),
                        ),
                      );
                      return;
                    }
                    if (fareValue < min || fareValue > max) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Fare must be between min and max'),
                        ),
                      );
                      return;
                    }
                    final hub = transportEndpointFor(muni);
                    final endpointSlug = municipalitySlug(hub.name);
                    final spotSlug = touristSpotProfileStorageSlug(spot.name);
                    final id = hubSpotTransportFeeDocId(
                      endpointSlug,
                      spotSlug,
                      HubSpotLegDirection.hubToSpot,
                    );
                    if (hubSpotTransportFeesByDocId.containsKey(id) ||
                        (_hubMatrixFallback?.any((f) => f.id == id) ?? false)) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('This hub → spot fare already exists'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(
                      ctx,
                      HubSpotTransportFee(
                        id: id,
                        fromEndpointName: hubCtrl.text.trim(),
                        fromEndpointType: hub.kind,
                        municipality: muni.name,
                        municipalitySlug: municipalitySlug(muni.name),
                        toTouristSpotSlug: spotSlug,
                        toTouristSpotName: spot.name,
                        fareMin: min,
                        fareMax: max,
                        fare: fareValue,
                        routeType: 'tricycle',
                        direction: HubSpotLegDirection.hubToSpot,
                      ),
                    );
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      minCtrl.dispose();
      maxCtrl.dispose();
      fareCtrl.dispose();
      hubCtrl.dispose();
    }

    if (created == null || !mounted) return;
    setState(() => _savingDocId = created!.id);
    await _persistFee(
      () => saveHubSpotTransportFeeToFirestore(created!),
      'Added ${created.toTouristSpotName} fare',
    );
    if (mounted) setState(() => _savingDocId = null);
  }

  Future<void> _deleteHubSpotFee(HubSpotTransportFee fee) async {
    final ok = await _confirmDelete(
      'Delete fare?',
      'Remove hub → spot fare for ${fee.toTouristSpotName}?',
    );
    if (!ok || !mounted) return;
    setState(() => _savingDocId = fee.id);
    try {
      await refreshAuthRoleClaims();
      if (hubSpotTransportFeesByDocId.containsKey(fee.id)) {
        await deleteHubSpotTransportFeeFromFirestore(fee.id);
      } else {
        _removedHubFallbackIds.add(fee.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted ${fee.toTouristSpotName}'),
          backgroundColor: _accent,
        ),
      );
      setState(_rebuildFilteredLists);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingDocId = null);
    }
  }

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    );
  }

  Widget _municipalityDropdown({
    required String label,
    required String value,
    required List<String> names,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: _dropdownDecoration(label),
      isExpanded: true,
      items: names
          .map(
            (n) => DropdownMenuItem(
              value: n,
              child: Text(n, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  int? _parsePhpInt(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  double? _parseKm(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    return double.tryParse(t.replaceAll(RegExp(r'[^0-9.]'), ''));
  }

  Widget _hubTypeSegmentedControl({
    required String endpointType,
    required ValueChanged<String> onChanged,
  }) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'terminal', label: Text('Terminal')),
        ButtonSegment(value: 'stop', label: Text('Bus stop')),
      ],
      selected: {endpointType},
      onSelectionChanged: (selected) => onChanged(selected.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return AppColors.textDark;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _accent;
          return Colors.grey.shade100;
        }),
      ),
    );
  }

  Future<void> _editInterLguFee(TransportationFee fee) async {
    final fareCtrl = TextEditingController(text: '${fee.fare}');
    final distCtrl = TextEditingController(
      text: fee.estimatedDistance > 0
          ? fee.estimatedDistance.toStringAsFixed(1)
          : '',
    );
    final endpointCtrl = TextEditingController(text: fee.endpointName);
    var endpointType = fee.endpointType == 'stop' ? 'stop' : 'terminal';
    final formKey = GlobalKey<FormState>();

    TransportationFee? updated;
    try {
      updated = await showDialog<TransportationFee>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            title: const Text('Edit route fare'),
            content: SizedBox(
              width: math.min(420, MediaQuery.sizeOf(ctx).width - 40),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${fee.fromMunicipality} → ${fee.toMunicipality}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _dialogField(
                        controller: fareCtrl,
                        label: 'Fare (₱)',
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = _parsePhpInt(v ?? '');
                          if (n == null || n < 0) return 'Enter a valid fare';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Hub type at destination',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textGrey.withValues(alpha: 0.95),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _hubTypeSegmentedControl(
                        endpointType: endpointType,
                        onChanged: (v) => setDialog(() => endpointType = v),
                      ),
                      const SizedBox(height: 12),
                      _dialogField(
                        controller: endpointCtrl,
                        label: 'Ends at (hub name)',
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      _dialogField(
                        controller: distCtrl,
                        label: 'Distance (km)',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          final n = _parseKm(v ?? '');
                          if (n == null || n < 0) {
                            return 'Enter a valid distance';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.pop(
                    ctx,
                    fee.copyWith(
                      fare: _parsePhpInt(fareCtrl.text)!,
                      endpointType: endpointType,
                      endpointName: endpointCtrl.text.trim(),
                      estimatedDistance: _parseKm(distCtrl.text) ?? 0,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      fareCtrl.dispose();
      distCtrl.dispose();
      endpointCtrl.dispose();
    }

    if (updated == null || !mounted) return;

    setState(() => _savingDocId = fee.id);
    try {
      await refreshAuthRoleClaims();
      await saveTransportationFeeToFirestore(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${updated.fromMunicipality} → ${updated.toMunicipality}: ${formatFarePhp(updated.fare)}',
          ),
          backgroundColor: _accent,
        ),
      );
      setState(() {
        _rebuildFilteredLists();
      });
    } catch (e) {
      if (!mounted) return;
      final denied = e.toString().contains('permission-denied');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? 'Save denied. Sign in as admin/staff, then try again.'
                : 'Could not save: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingDocId = null);
    }
  }

  Future<void> _editHubSpotFee(HubSpotTransportFee fee) async {
    final minCtrl = TextEditingController(text: '${fee.fareMin}');
    final maxCtrl = TextEditingController(text: '${fee.fareMax}');
    final fareCtrl = TextEditingController(text: '${fee.fare}');
    final formKey = GlobalKey<FormState>();

    HubSpotTransportFee? updated;
    try {
      updated = await showDialog<HubSpotTransportFee>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: const Text('Edit hub → spot fare'),
        content: SizedBox(
          width: math.min(420, MediaQuery.sizeOf(ctx).width - 40),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${fee.municipality} · ${fee.toTouristSpotName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  fee.fromEndpointName,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _dialogField(
                        controller: minCtrl,
                        label: 'Min (₱)',
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = _parsePhpInt(v ?? '');
                          if (n == null || n < 0) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dialogField(
                        controller: maxCtrl,
                        label: 'Max (₱)',
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = _parsePhpInt(v ?? '');
                          if (n == null || n < 0) return 'Invalid';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _dialogField(
                  controller: fareCtrl,
                  label: 'Fare used (₱)',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = _parsePhpInt(v ?? '');
                    if (n == null || n < 0) return 'Enter a valid fare';
                    return null;
                  },
                ),
              ],
            ),
            ),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final min = _parsePhpInt(minCtrl.text)!;
              final max = _parsePhpInt(maxCtrl.text)!;
              final fareValue = _parsePhpInt(fareCtrl.text)!;
              if (min > max) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Min fare cannot exceed max fare'),
                  ),
                );
                return;
              }
              if (fareValue < min || fareValue > max) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Fare must be between min and max'),
                  ),
                );
                return;
              }
              Navigator.pop(
                ctx,
                fee.copyWith(fareMin: min, fareMax: max, fare: fareValue),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    } finally {
      minCtrl.dispose();
      maxCtrl.dispose();
      fareCtrl.dispose();
    }

    if (updated == null || !mounted) return;

    setState(() => _savingDocId = fee.id);
    try {
      await refreshAuthRoleClaims();
      await saveHubSpotTransportFeeToFirestore(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${updated.toTouristSpotName}: ${formatFarePhp(updated.fare)}',
          ),
          backgroundColor: _accent,
        ),
      );
      setState(() {
        _rebuildFilteredLists();
      });
    } catch (e) {
      if (!mounted) return;
      final denied = e.toString().contains('permission-denied');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? 'Save denied. Sign in as admin/staff, then try again.'
                : 'Could not save: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingDocId = null);
    }
  }

  Widget _dialogField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 13, color: AppColors.textDark),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _th(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11.5,
          height: 1.1,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  Widget _td(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: child,
    );
  }

  Widget _tdAction(Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 5, 10, 5),
      child: child,
    );
  }

  Widget _ellipsis(String text, {TextStyle? style}) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style ?? _cellStyle,
    );
  }

  Widget _sectionTitle(String text, {required int count}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textGrey,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Text(
          '$count rows',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _accent,
          ),
        ),
      ],
    );
  }

  Widget _emptyHint(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 13,
          color: AppColors.textGrey.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}
