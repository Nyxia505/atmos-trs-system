import 'package:flutter/material.dart';

import '../../data.dart';
import '../../services/reports/report_format.dart';
import '../../services/reports/report_models.dart';
import '../../services/reports/reports_service.dart';
import '../tourism_plan_ui.dart';

/// Filter row above the analytics section.
///
/// Holds a draft selection so nothing recomputes until the administrator
/// presses Apply; Reset clears back to "all records".
class ReportFilterBar extends StatefulWidget {
  final ReportKind kind;
  final ReportFilters applied;
  final ReportFilterOptions options;
  final ValueChanged<ReportFilters> onApply;
  final VoidCallback onReset;
  final bool busy;

  const ReportFilterBar({
    super.key,
    required this.kind,
    required this.applied,
    required this.options,
    required this.onApply,
    required this.onReset,
    this.busy = false,
  });

  @override
  State<ReportFilterBar> createState() => _ReportFilterBarState();
}

class _ReportFilterBarState extends State<ReportFilterBar> {
  late ReportFilters _draft = widget.applied;

  @override
  void didUpdateWidget(ReportFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow external changes (report switch, Reset) without stomping on edits.
    if (oldWidget.applied != widget.applied) {
      _draft = widget.applied;
    }
    if (oldWidget.kind != widget.kind) {
      _draft = widget.applied;
    }
  }

  bool _supports(ReportFilterField field) =>
      widget.kind.supportedFilters.contains(field);

  bool get _dirty => _draft != widget.applied;

  /// Tourist spots offered in the draft filters, limited to the chosen LGU when
  /// Single Municipality is active.
  List<String> _touristSpotsForDraft() {
    final lguName = _draft.effectiveMunicipality;
    if (lguName == null) {
      // Overall draft: prefer the full catalog names when options were narrowed
      // by a previously applied LGU filter.
      if (widget.applied.effectiveMunicipality != null) {
        return allSpots.map((s) => s.name).toSet().toList()..sort();
      }
      return widget.options.touristSpots;
    }
    Municipality? municipality;
    for (final m in municipalities) {
      if (m.name == lguName || m.shortName == lguName) {
        municipality = m;
        break;
      }
    }
    if (municipality == null) return widget.options.touristSpots;
    return allSpots
        .where((s) => touristSpotBelongsToMunicipality(s, municipality!))
        .map((s) => s.name)
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _draft.dateRange,
      helpText: 'Select report date range',
      saveText: 'Use range',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.primary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _draft = _draft.copyWith(dateRange: picked));
  }

  @override
  Widget build(BuildContext context) {
    final range = _draft.dateRange;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: TourismPlanUi.planCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.filter_alt_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Report filters',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (_dirty)
                const Text(
                  'Not applied yet',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          if (_supports(ReportFilterField.municipality)) ...[
            const SizedBox(height: 14),
            _scopeSelector(),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (_supports(ReportFilterField.dateRange))
                _field(
                  label: 'Date range',
                  child: InkWell(
                    onTap: widget.busy ? null : _pickRange,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _inputDecoration(),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              range == null
                                  ? 'All dates'
                                  : '${formatReportDate(range.start)} – '
                                        '${formatReportDate(range.end)}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: range == null
                                    ? AppColors.textGrey
                                    : AppColors.textDark,
                              ),
                            ),
                          ),
                          if (range != null)
                            IconButton(
                              tooltip: 'Clear date range',
                              iconSize: 16,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.close),
                              color: AppColors.textGrey,
                              onPressed: widget.busy
                                  ? null
                                  : () => setState(
                                      () => _draft = _draft.copyWith(
                                        clearDateRange: true,
                                      ),
                                    ),
                            )
                          else
                            const Icon(
                              Icons.date_range_outlined,
                              size: 17,
                              color: AppColors.textGrey,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_supports(ReportFilterField.touristSpot))
                _field(
                  label: 'Tourist spot',
                  child: _dropdown(
                    value: _draft.touristSpot,
                    hint: 'All tourist spots',
                    items: _touristSpotsForDraft(),
                    onChanged: (v) => setState(
                      () => _draft = v == null
                          ? _draft.copyWith(clearTouristSpot: true)
                          : _draft.copyWith(touristSpot: v),
                    ),
                  ),
                ),
              if (_supports(ReportFilterField.event))
                _field(
                  label: 'Event',
                  child: _dropdown(
                    value: _draft.eventId,
                    hint: 'All events',
                    items: [for (final e in widget.options.events) e.id],
                    labelFor: (id) {
                      for (final e in widget.options.events) {
                        if (e.id == id) return e.title;
                      }
                      return id;
                    },
                    onChanged: (v) => setState(
                      () => _draft = v == null
                          ? _draft.copyWith(clearEvent: true)
                          : _draft.copyWith(eventId: v),
                    ),
                  ),
                ),
              if (_supports(ReportFilterField.transportType))
                _field(
                  label: 'Transportation type',
                  child: _dropdown(
                    value: _draft.transportType,
                    hint: 'All types',
                    items: widget.options.transportTypes,
                    labelFor: formatTransportType,
                    onChanged: (v) => setState(
                      () => _draft = v == null
                          ? _draft.copyWith(clearTransportType: true)
                          : _draft.copyWith(transportType: v),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: widget.busy
                    ? null
                    : () {
                        if (_draft.needsMunicipalitySelection) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Select a municipality / LGU before applying '
                                'the Single Municipality filter.',
                              ),
                            ),
                          );
                          return;
                        }
                        widget.onApply(_draft);
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Apply Filters'),
              ),
              OutlinedButton.icon(
                onPressed: widget.busy || (_draft.isEmpty && !_dirty)
                    ? null
                    : () {
                        setState(() => _draft = ReportFilters.none);
                        widget.onReset();
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textDark,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset Filters'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Overall (every LGU) versus a single municipality. Applying Single without
  /// an LGU is blocked until the administrator picks one from the dropdown.
  Widget _scopeSelector() {
    final lgus = widget.options.municipalities;
    final single = _draft.scope == ReportScope.singleMunicipality;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Report scope',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textGrey,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _scopeChoice(
              label: 'Overall report',
              caption: 'All municipalities',
              icon: Icons.public_outlined,
              selected: !single,
              onTap: () => setState(
                () => _draft = _draft.copyWith(
                  scope: ReportScope.overall,
                  clearMunicipality: true,
                ),
              ),
            ),
            _scopeChoice(
              label: 'Single municipality',
              caption: lgus.isEmpty ? 'No LGUs loaded' : 'One LGU only',
              icon: Icons.location_city_outlined,
              selected: single,
              onTap: lgus.isEmpty
                  ? null
                  : () => setState(
                      () => _draft = _draft.copyWith(
                        scope: ReportScope.singleMunicipality,
                      ),
                    ),
            ),
            if (single)
              SizedBox(
                width: 236,
                child: _dropdown(
                  value: _draft.municipality,
                  hint: 'Choose a municipality',
                  items: lgus,
                  allowAll: false,
                  onChanged: (v) => setState(
                    () => _draft = v == null
                        ? _draft.copyWith(
                            scope: ReportScope.singleMunicipality,
                            clearMunicipality: true,
                          )
                        : _draft.copyWith(
                            scope: ReportScope.singleMunicipality,
                            municipality: v,
                            clearTouristSpot: true,
                          ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _scopeChoice({
    required String label,
    required String caption,
    required IconData icon,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null && !widget.busy;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.insetSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : Colors.black.withValues(alpha: 0.08),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? AppColors.primary : AppColors.textGrey,
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: enabled || selected
                        ? AppColors.textDark
                        : AppColors.textGrey,
                  ),
                ),
                Text(
                  caption,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? AppColors.primary : AppColors.textGrey,
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _inputDecoration() => BoxDecoration(
    color: AppColors.insetSurface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
  );

  Widget _field({required String label, required Widget child}) {
    return SizedBox(
      width: 236,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _dropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String Function(String)? labelFor,

    /// Whether to offer the "everything" entry. The scope dropdown omits it
    /// because clearing the LGU is what the Overall choice is for.
    bool allowAll = true,
  }) {
    // A stale selection (e.g. a spot removed from the catalog) would make
    // DropdownButton assert, so fall back to the "all" state.
    final safeValue = value != null && items.contains(value) ? value : null;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: _inputDecoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: safeValue,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(
            Icons.expand_more,
            size: 18,
            color: AppColors.textGrey,
          ),
          style: const TextStyle(fontSize: 13, color: AppColors.textDark),
          hint: Text(
            hint,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textGrey),
          ),
          onChanged: widget.busy || items.isEmpty ? null : onChanged,
          items: [
            if (allowAll)
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  hint,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textGrey,
                  ),
                ),
              ),
            for (final item in items)
              DropdownMenuItem<String?>(
                value: item,
                child: Text(
                  labelFor == null ? item : labelFor(item),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
