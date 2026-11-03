import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/dot_report_entity_scope.dart';
import 'package:atmos_trs_system/utils/dot_report_preview.dart';
import 'package:trip_plan/services/reports/report_format.dart';
import 'package:trip_plan/services/reports/report_models.dart';
import 'package:trip_plan/services/reports/reports_service.dart';
import 'package:trip_plan/trip_planner_utils.dart'
    show matchMunicipalityByLocalityHint;

/// OPTACA-only catalog entries for Events & Announcements / Matrix Fares.
/// Not part of [kDotFormCatalog], so LGU / hotel dashboards stay unchanged.
abstract final class PortalSummaryDotReport {
  static const evt1Id = 'optaca_evt1';
  static const evt2Id = 'optaca_evt2';
  static const evt3Id = 'optaca_evt3';
  static const ann1Id = 'optaca_ann1';
  static const ann2Id = 'optaca_ann2';
  static const ean1Id = 'optaca_ean1';
  static const mfx1Id = 'optaca_mfx1';
  static const mfx2Id = 'optaca_mfx2';
  static const mfx3Id = 'optaca_mfx3';
  static const mfx4Id = 'optaca_mfx4';
  static const mfx5Id = 'optaca_mfx5';

  static const eventsOnlyId = evt1Id;
  static const announcementsOnlyId = ann1Id;
  static const eventsCombinedId = ean1Id;
  static const matrixFareId = mfx1Id;
  static const matrixMunicipalityId = mfx2Id;
  static const matrixTypeId = mfx3Id;
  static const matrixCombinedId = mfx5Id;

  static const eventsForms = <DotFormCatalogEntry>[
    DotFormCatalogEntry(
      id: evt1Id,
      code: 'EVT 1',
      title: 'EVT 1 — Tourism Events Record',
      subtitle: 'Scheduled tourism events and activities.',
      category: DotFormCategory.optaca,
      fillMode: DotFormFillMode.atmosDerived,
      objectFilename: '',
      localFilename: '',
      searchTags: [
        'evt 1',
        'events',
        'record',
        'calendar',
        'venue',
        'activities',
      ],
      offersOfficialBlankSecondary: false,
    ),
    DotFormCatalogEntry(
      id: evt2Id,
      code: 'EVT 2',
      title: 'EVT 2 — Municipal Events Report',
      subtitle: 'Events in the selected city or municipality.',
      category: DotFormCategory.optaca,
      fillMode: DotFormFillMode.atmosDerived,
      objectFilename: '',
      localFilename: '',
      searchTags: ['evt 2', 'events', 'municipal', 'lgu', 'city'],
      offersOfficialBlankSecondary: false,
    ),
    DotFormCatalogEntry(
      id: evt3Id,
      code: 'EVT 3',
      title: 'EVT 3 — Tourism Events Summary',
      subtitle: 'Summary of scheduled tourism events.',
      category: DotFormCategory.optaca,
      fillMode: DotFormFillMode.atmosDerived,
      objectFilename: '',
      localFilename: '',
      searchTags: ['evt 3', 'events', 'summary', 'calendar'],
      offersOfficialBlankSecondary: false,
    ),
    DotFormCatalogEntry(
      id: ann1Id,
      code: 'ANN 1',
      title: 'ANN 1 — Public Announcements Record',
      subtitle: 'Public announcements and tourism notices.',
      category: DotFormCategory.optaca,
      fillMode: DotFormFillMode.atmosDerived,
      objectFilename: '',
      localFilename: '',
      searchTags: ['ann 1', 'announcements', 'notices', 'public', 'record'],
      offersOfficialBlankSecondary: false,
    ),
    DotFormCatalogEntry(
      id: ann2Id,
      code: 'ANN 2',
      title: 'ANN 2 — Municipal Announcements Report',
      subtitle: 'Announcements for the selected city or municipality.',
      category: DotFormCategory.optaca,
      fillMode: DotFormFillMode.atmosDerived,
      objectFilename: '',
      localFilename: '',
      searchTags: ['ann 2', 'announcements', 'municipal', 'lgu', 'notices'],
      offersOfficialBlankSecondary: false,
    ),
    DotFormCatalogEntry(
      id: ean1Id,
      code: 'EAN 1',
      title: 'EAN 1 — Events & Announcements Summary',
      subtitle: 'Complete report of events and announcements.',
      category: DotFormCategory.optaca,
      fillMode: DotFormFillMode.atmosDerived,
      objectFilename: '',
      localFilename: '',
      searchTags: [
        'ean 1',
        'events',
        'announcements',
        'combined',
        'summary',
      ],
      offersOfficialBlankSecondary: false,
    ),
  ];

  static const matrixForms = <DotFormCatalogEntry>[
    DotFormCatalogEntry(
      id: mfx1Id,
      code: 'MFX 1',
      title: 'MFX 1 — Transportation Fare Matrix',
      subtitle: 'Published transportation fares by route.',
      category: DotFormCategory.optaca,
      fillMode: DotFormFillMode.atmosDerived,
      objectFilename: '',
      localFilename: '',
      searchTags: ['mfx 1', 'matrix', 'fares', 'routes', 'transport'],
      offersOfficialBlankSecondary: false,
    ),
    DotFormCatalogEntry(
      id: mfx2Id,
      code: 'MFX 2',
      title: 'MFX 2 — Municipal Fare Matrix',
      subtitle: 'Fare matrix for the selected city or municipality.',
      category: DotFormCategory.optaca,
      fillMode: DotFormFillMode.atmosDerived,
      objectFilename: '',
      localFilename: '',
      searchTags: ['mfx 2', 'municipal', 'lgu', 'fares', 'matrix'],
      offersOfficialBlankSecondary: false,
    ),
    DotFormCatalogEntry(
      id: mfx3Id,
      code: 'MFX 3',
      title: 'MFX 3 — Route Fare Summary',
      subtitle: 'Fares grouped by travel route.',
      category: DotFormCategory.optaca,
      fillMode: DotFormFillMode.atmosDerived,
      objectFilename: '',
      localFilename: '',
      searchTags: [
        'mfx 3',
        'route',
        'summary',
        'jeepney',
        'bus',
        'tricycle',
      ],
      offersOfficialBlankSecondary: false,
    ),
    DotFormCatalogEntry(
      id: mfx4Id,
      code: 'MFX 4',
      title: 'MFX 4 — Terminal-to-Terminal Fare Report',
      subtitle: 'Inter-LGU terminal to terminal fares.',
      category: DotFormCategory.optaca,
      fillMode: DotFormFillMode.atmosDerived,
      objectFilename: '',
      localFilename: '',
      searchTags: ['mfx 4', 'terminal', 'inter-lgu', 'fares', 'routes'],
      offersOfficialBlankSecondary: false,
    ),
    DotFormCatalogEntry(
      id: mfx5Id,
      code: 'MFX 5',
      title: 'MFX 5 — Provincial Fare Matrix',
      subtitle: 'Province-wide fare matrix and summaries.',
      category: DotFormCategory.optaca,
      fillMode: DotFormFillMode.atmosDerived,
      objectFilename: '',
      localFilename: '',
      searchTags: ['mfx 5', 'provincial', 'matrix', 'fares', 'combined'],
      offersOfficialBlankSecondary: false,
    ),
  ];

  static IconData iconFor(String formId) {
    return switch (formId) {
      evt1Id || evt2Id || evt3Id => Icons.event_note_outlined,
      ann1Id || ann2Id => Icons.campaign_outlined,
      ean1Id => Icons.event_available_outlined,
      mfx1Id || mfx5Id => Icons.grid_on_outlined,
      mfx2Id => Icons.location_city_outlined,
      mfx3Id => Icons.directions_bus_outlined,
      mfx4Id => Icons.route_outlined,
      _ => Icons.auto_awesome_outlined,
    };
  }

  static List<DotFormCatalogEntry> formsFor(DotReportEntityKind kind) {
    return switch (kind) {
      DotReportEntityKind.eventsAnnouncements => eventsForms,
      DotReportEntityKind.matrixFares => matrixForms,
      _ => const [],
    };
  }

  static ReportKind? reportKindOf(DotReportEntityKind kind) {
    return switch (kind) {
      DotReportEntityKind.eventsAnnouncements =>
        ReportKind.eventsAnnouncements,
      DotReportEntityKind.matrixFares => ReportKind.matrixFares,
      _ => null,
    };
  }

  static bool appliesDateRange(DotReportEntityKind kind) =>
      kind == DotReportEntityKind.eventsAnnouncements;

  static ReportFilters filters({
    required DotReportEntityKind kind,
    required DateTime? start,
    required DateTime? end,
    required String municipalityName,
  }) {
    var mun = municipalityName.trim();
    if (mun.isNotEmpty) {
      final matched = matchMunicipalityByLocalityHint(mun);
      if (matched != null) mun = matched.name;
    }
    DateTimeRange? range;
    if (appliesDateRange(kind) && start != null && end != null) {
      final a = DateTime(start.year, start.month, start.day);
      final b = DateTime(end.year, end.month, end.day);
      range = a.isAfter(b)
          ? DateTimeRange(start: b, end: a)
          : DateTimeRange(start: a, end: b);
    }
    return ReportFilters(
      scope: mun.isEmpty ? ReportScope.overall : ReportScope.singleMunicipality,
      municipality: mun.isEmpty ? null : mun,
      dateRange: range,
    );
  }

  static Future<ReportDataset> buildDataset({
    required DotReportEntityKind kind,
    required DotFormCatalogEntry form,
    required DateTime? start,
    required DateTime? end,
    required String municipalityName,
    bool refresh = false,
  }) async {
    final reportKind = reportKindOf(kind);
    if (reportKind == null) {
      throw StateError('Not a portal summary kind: $kind');
    }
    final raw = await ReportsService.build(
      kind: reportKind,
      filters: filters(
        kind: kind,
        start: start,
        end: end,
        municipalityName: municipalityName,
      ),
      refresh: refresh,
    );
    return applyForm(raw, form);
  }

  static ReportDataset applyForm(
    ReportDataset dataset,
    DotFormCatalogEntry form,
  ) {
    final source = _sourceTables(dataset, form);
    final content = layoutTables(
      dataset.withTables(source),
      form,
    );
    final metrics = metricsFor(form, dataset, content);
    final notes = _warningsFor(form, dataset, content);
    return dataset.withTables(
      [
        _summaryTable(metrics),
        ...content,
      ],
      extraFilters: [
        ('Template', form.code),
        ('Form type', form.title),
      ],
      titleOverride: form.title,
      metrics: metrics,
      warning: notes.isEmpty ? dataset.warning : notes.join(' '),
    );
  }

  static List<ReportTable> _sourceTables(
    ReportDataset dataset,
    DotFormCatalogEntry form,
  ) {
    final titles = tableTitlesFor(form.id);
    if (titles == null) return dataset.tables;
    return [
      for (final t in dataset.tables)
        if (_matchesSourceTitle(t.title, titles)) t,
    ];
  }

  /// Source table titles in [ReportsService] that belong to [formId].
  static Set<String>? tableTitlesFor(String formId) {
    return switch (formId) {
      evt1Id || evt2Id || evt3Id => const {'Events'},
      ann1Id || ann2Id => const {'Public announcements'},
      ean1Id => const {'Events', 'Public announcements'},
      mfx1Id => const {'Fare matrix'},
      mfx2Id => const {'Fare matrix', 'Fare by municipality'},
      mfx3Id => const {'Fare matrix'},
      mfx4Id => const {kTerminalFaresSourceTitle},
      mfx5Id => const {
          'Fare matrix',
          'Fare by municipality',
          'Fare by transportation type',
          kTerminalFaresSourceTitle,
        },
      _ => null,
    };
  }

  /// Template-specific sections. [dataset.tables] must be the raw source
  /// tables from [ReportsService], not an already-applied template.
  static List<ReportTable> layoutTables(
    ReportDataset dataset,
    DotFormCatalogEntry form,
  ) {
    ReportTable? named(String title) {
      for (final t in dataset.tables) {
        if (t.title == title) return t;
      }
      if (title == kTerminalFaresSourceTitle ||
          title == kTerminalFaresTableTitle) {
        for (final t in dataset.tables) {
          if (t.title == kTerminalFaresSourceTitle ||
              t.title == kTerminalFaresTableTitle) {
            return t;
          }
        }
      }
      return null;
    }

    final events = named('Events');
    final announcements = named('Public announcements');
    final fareMatrix = named('Fare matrix');
    final fareByMun = named('Fare by municipality');
    final fareByType = named('Fare by transportation type');
    final terminal = named(kTerminalFaresSourceTitle);
    final lgu = dataset.filters.effectiveMunicipality;

    List<ReportTable> of(List<ReportTable?> tables) => [
          for (final t in tables)
            if (t != null) t,
        ];

    return switch (form.id) {
      evt1Id => of([
          _orEmpty(
            events,
            title: 'Tourism event records',
            columns: _eventRecordColumns,
          ),
        ]),
      evt2Id => of([
          _municipalEventSummary(events),
          _municipalEventListings(events),
        ]),
      evt3Id => of([
          _countByUnique(
            events,
            groupColumn: 'Category',
            title: 'Events by category',
          ),
          _countByUnique(
            events,
            groupColumn: 'Status',
            title: 'Events by status',
          ),
          _municipalEventSummary(events),
          _eventsByMonth(events),
        ]),
      ann1Id => of([
          _orEmpty(
            announcements,
            title: 'Public announcement records',
            columns: _announcementRecordColumns,
          ),
        ]),
      ann2Id => _announcementsMunicipal(announcements, lgu),
      ean1Id => of([
          _countByUnique(
            events,
            groupColumn: 'Category',
            title: 'Events by category',
          ),
          _municipalEventSummary(events),
          _orEmpty(
            events,
            title: 'Tourism event records',
            columns: _eventRecordColumns,
          ),
          _orEmpty(
            announcements,
            title: 'Public announcement records',
            columns: _announcementRecordColumns,
          ),
        ]),
      mfx1Id => of([
          _orEmpty(
            fareMatrix,
            title: 'Transportation fare matrix',
            columns: _fareMatrixColumns,
          ),
        ]),
      mfx2Id => of([
          _orEmpty(
            fareByMun,
            title: 'Fares by municipality',
            columns: _fareByMunColumns,
          ),
          _orEmpty(
            fareMatrix,
            title: 'Municipal fare records',
            columns: _fareMatrixColumns,
          ),
        ]),
      mfx3Id => of([_faresByRoute(fareMatrix)]),
      mfx4Id => of([
          _orEmpty(
            terminal,
            title: kTerminalFaresTableTitle,
            columns: _fareMatrixColumns,
          ),
        ]),
      mfx5Id => of([
          _orEmpty(
            fareByMun,
            title: 'Fares by municipality',
            columns: _fareByMunColumns,
          ),
          _faresByRoute(fareMatrix),
          _orEmpty(
            fareByType,
            title: 'Fares by transportation type',
            columns: _fareByTypeColumns,
          ),
          _orEmpty(
            fareMatrix,
            title: 'Provincial fare matrix',
            columns: _fareMatrixColumns,
          ),
          _orEmpty(
            terminal,
            title: kTerminalFaresTableTitle,
            columns: _fareMatrixColumns,
          ),
        ]),
      _ => dataset.tables,
    };
  }

  static const _eventRecordColumns = [
    'Event',
    'Category',
    'Municipality',
    'Venue',
    'Date & time',
    'Status',
    'Check-ins that day',
  ];
  static const _announcementRecordColumns = [
    'Announcement',
    'Published',
    'Details',
  ];
  /// Source table title emitted by [ReportsService._buildMatrixFares].
  static const kTerminalFaresSourceTitle = 'Terminal to terminal fares';

  /// Display title (and Excel sheet name) for the inter-LGU fare table.
  static const kTerminalFaresTableTitle = 'Terminal-to-Terminal Fares';

  static bool _matchesSourceTitle(String title, Set<String> wanted) {
    if (wanted.contains(title)) return true;
    if (title == kTerminalFaresTableTitle &&
        wanted.contains(kTerminalFaresSourceTitle)) {
      return true;
    }
    if (title == kTerminalFaresSourceTitle &&
        wanted.contains(kTerminalFaresTableTitle)) {
      return true;
    }
    return false;
  }

  static const _fareMatrixColumns = [
    'Municipality',
    'Starting point',
    'Destination / tourist spot',
    'Transportation type',
    'Fare',
    'Distance',
    'Estimated travel time',
  ];
  static const _fareByMunColumns = [
    'Municipality',
    'Routes',
    'Average fare',
    'Lowest',
    'Highest',
  ];
  static const _fareByTypeColumns = [
    'Transportation type',
    'Routes',
    'Average fare',
    'Lowest',
    'Highest',
  ];

  static ReportTable _orEmpty(
    ReportTable? source, {
    required String title,
    required List<String> columns,
  }) {
    if (source == null) {
      return ReportTable(title: title, columns: columns, rows: const []);
    }
    final index = [for (final c in columns) _colFlexible(source, c)];
    final mapped = index.every((i) => i >= 0);
    return ReportTable(
      title: title,
      columns: mapped ? columns : source.columns,
      rows: mapped
          ? [
              for (final row in source.rows)
                [
                  for (final i in index) i < row.length ? row[i] : '',
                ],
            ]
          : source.rows,
      numericColumns: mapped
          ? {
              for (var c = 0; c < index.length; c++)
                if (index[c] >= 0 && source.numericColumns.contains(index[c]))
                  c,
            }
          : source.numericColumns,
    );
  }

  static ReportTable _summaryTable(List<ReportMetric> metrics) {
    return ReportTable(
      title: 'Summary statistics',
      columns: const ['Metric', 'Value', 'Detail'],
      rows: [
        for (final m in metrics) [m.label, m.value, m.caption ?? ''],
      ],
    );
  }

  static List<String> _splitLgus(String cell) {
    final t = cell.trim();
    if (t.isEmpty || t == '—') return const ['—'];
    return [
      for (final part in t.split(';'))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  static String _cell(List<String> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index];
  }

  static int _col(ReportTable table, String name) => table.columns.indexOf(name);

  static int _colFlexible(ReportTable table, String name) {
    final exact = _col(table, name);
    if (exact >= 0) return exact;
    final target = name.trim().toLowerCase();
    for (var i = 0; i < table.columns.length; i++) {
      if (table.columns[i].trim().toLowerCase() == target) return i;
    }
    return -1;
  }

  static String _eventIdentity(List<String> row, int eventIdx, int dateIdx) {
    final title = _cell(row, eventIdx);
    final date = _cell(row, dateIdx);
    return date.isEmpty ? title : '$title\u0000$date';
  }

  static int _parseCount(String raw) {
    return int.tryParse(raw.replaceAll(',', '').trim()) ?? 0;
  }

  /// Unique events per municipality. Multi-LGU events count once in each
  /// city they belong to, without summing check-ins across those cities.
  static ReportTable _municipalEventSummary(ReportTable? events) {
    const columns = ['Municipality', 'Unique events', 'Upcoming', 'Completed'];
    if (events == null || events.isEmpty) {
      return const ReportTable(
        title: 'Events by municipality',
        columns: columns,
        numericColumns: {1, 2, 3},
        rows: [],
      );
    }
    final munIdx = _col(events, 'Municipality');
    final statusIdx = _col(events, 'Status');
    final eventIdx = _col(events, 'Event');
    final dateIdx = _col(events, 'Date & time');
    final perLgu = <String, Set<String>>{};
    final upcoming = <String, Set<String>>{};
    final completed = <String, Set<String>>{};
    for (final row in events.rows) {
      final id = _eventIdentity(row, eventIdx, dateIdx);
      final status = _cell(row, statusIdx).toLowerCase();
      for (final lgu in _splitLgus(_cell(row, munIdx))) {
        perLgu.putIfAbsent(lgu, () => {}).add(id);
        if (status == 'upcoming') {
          upcoming.putIfAbsent(lgu, () => {}).add(id);
        } else {
          completed.putIfAbsent(lgu, () => {}).add(id);
        }
      }
    }
    final keys = perLgu.keys.toList()
      ..sort((a, b) => perLgu[b]!.length.compareTo(perLgu[a]!.length));
    return ReportTable(
      title: 'Events by municipality',
      columns: columns,
      numericColumns: const {1, 2, 3},
      rows: [
        for (final key in keys)
          [
            key,
            perLgu[key]!.length.toString(),
            (upcoming[key]?.length ?? 0).toString(),
            (completed[key]?.length ?? 0).toString(),
          ],
      ],
    );
  }

  static ReportTable _municipalEventListings(ReportTable? events) {
    const columns = [
      'Municipality',
      'Event',
      'Category',
      'Venue',
      'Date & time',
      'Status',
    ];
    if (events == null || events.isEmpty) {
      return const ReportTable(
        title: 'Municipal event listings',
        columns: columns,
        rows: [],
      );
    }
    final munIdx = _col(events, 'Municipality');
    final eventIdx = _col(events, 'Event');
    final catIdx = _col(events, 'Category');
    final venueIdx = _col(events, 'Venue');
    final dateIdx = _col(events, 'Date & time');
    final statusIdx = _col(events, 'Status');
    final rows = <List<String>>[
      for (final row in events.rows)
        for (final lgu in _splitLgus(_cell(row, munIdx)))
          [
            lgu,
            _cell(row, eventIdx),
            _cell(row, catIdx),
            _cell(row, venueIdx),
            _cell(row, dateIdx),
            _cell(row, statusIdx),
          ],
    ]..sort((a, b) {
        final byLgu = a[0].compareTo(b[0]);
        return byLgu != 0 ? byLgu : a[1].compareTo(b[1]);
      });
    return ReportTable(
      title: 'Municipal event listings',
      columns: columns,
      rows: rows,
    );
  }

  static ReportTable _countByUnique(
    ReportTable? source, {
    required String groupColumn,
    required String title,
  }) {
    if (source == null || source.isEmpty) {
      return ReportTable(
        title: title,
        columns: [groupColumn, 'Unique events'],
        numericColumns: const {1},
        rows: const [],
      );
    }
    final groupIdx = _col(source, groupColumn);
    final eventIdx = _col(source, 'Event');
    final dateIdx = _col(source, 'Date & time');
    final groups = <String, Set<String>>{};
    for (final row in source.rows) {
      final key = _cell(row, groupIdx).trim().isEmpty
          ? '—'
          : _cell(row, groupIdx).trim();
      groups
          .putIfAbsent(key, () => {})
          .add(_eventIdentity(row, eventIdx, dateIdx));
    }
    final keys = groups.keys.toList()
      ..sort((a, b) => groups[b]!.length.compareTo(groups[a]!.length));
    return ReportTable(
      title: title,
      columns: [groupColumn, 'Unique events'],
      numericColumns: const {1},
      rows: [
        for (final key in keys) [key, groups[key]!.length.toString()],
      ],
    );
  }

  static ReportTable _eventsByMonth(ReportTable? events) {
    const columns = ['Month', 'Unique events', 'Upcoming', 'Completed'];
    if (events == null || events.isEmpty) {
      return const ReportTable(
        title: 'Events by month',
        columns: columns,
        numericColumns: {1, 2, 3},
        rows: [],
      );
    }
    final dateIdx = _col(events, 'Date & time');
    final statusIdx = _col(events, 'Status');
    final eventIdx = _col(events, 'Event');
    final months = <String, Set<String>>{};
    final upcoming = <String, Set<String>>{};
    final completed = <String, Set<String>>{};
    final order = <String, DateTime>{};
    for (final row in events.rows) {
      final stamp = _monthKey(_cell(row, dateIdx));
      final id = _eventIdentity(row, eventIdx, dateIdx);
      months.putIfAbsent(stamp.label, () => {}).add(id);
      order.putIfAbsent(stamp.label, () => stamp.sort);
      if (_cell(row, statusIdx).toLowerCase() == 'upcoming') {
        upcoming.putIfAbsent(stamp.label, () => {}).add(id);
      } else {
        completed.putIfAbsent(stamp.label, () => {}).add(id);
      }
    }
    final keys = months.keys.toList()
      ..sort((a, b) => order[a]!.compareTo(order[b]!));
    return ReportTable(
      title: 'Events by month',
      columns: columns,
      numericColumns: const {1, 2, 3},
      rows: [
        for (final key in keys)
          [
            key,
            months[key]!.length.toString(),
            (upcoming[key]?.length ?? 0).toString(),
            (completed[key]?.length ?? 0).toString(),
          ],
      ],
    );
  }

  static ({String label, DateTime sort}) _monthKey(String raw) {
    const months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };
    final dmy = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})').firstMatch(raw);
    final mdy = RegExp(r'([A-Za-z]{3})\s+(\d{1,2}),\s+(\d{4})').firstMatch(raw);
    final monthName = dmy?.group(2) ?? mdy?.group(1);
    final yearText = dmy?.group(3) ?? mdy?.group(3);
    if (monthName == null || yearText == null) {
      return (label: raw.trim().isEmpty ? '—' : raw.trim(), sort: DateTime(0));
    }
    final month = months[monthName] ?? 1;
    final year = int.tryParse(yearText) ?? 0;
    return (
      label: formatMonthYear(year, month),
      sort: DateTime(year, month),
    );
  }

  static List<ReportTable> _announcementsMunicipal(
    ReportTable? announcements,
    String? lgu,
  ) {
    if (lgu != null && lgu.trim().isNotEmpty) {
      return [
        const ReportTable(
          title: 'Announcements by municipality',
          columns: ['Municipality', 'Announcements'],
          numericColumns: {1},
          rows: [],
        ),
        const ReportTable(
          title: 'Municipal announcements',
          columns: [
            'Municipality',
            'Announcement',
            'Published',
            'Details',
          ],
          rows: [],
        ),
      ];
    }
    final source = announcements ??
        const ReportTable(
          title: 'Public announcements',
          columns: _announcementRecordColumns,
          rows: [],
        );
    final publishedIdx = _col(source, 'Published');
    final titleIdx = _col(source, 'Announcement');
    final detailsIdx = _col(source, 'Details');
    final detailRows = [
      for (final row in source.rows)
        [
          'Province-wide (no LGU tag)',
          _cell(row, titleIdx),
          _cell(row, publishedIdx),
          _cell(row, detailsIdx),
        ],
    ];
    return [
      ReportTable(
        title: 'Announcements by municipality',
        columns: const ['Municipality', 'Announcements'],
        numericColumns: const {1},
        rows: source.isEmpty
            ? const []
            : [
                ['Province-wide (no LGU tag)', source.rows.length.toString()],
              ],
      ),
      ReportTable(
        title: 'Municipal announcements',
        columns: const [
          'Municipality',
          'Announcement',
          'Published',
          'Details',
        ],
        rows: detailRows,
      ),
    ];
  }

  static ReportTable _faresByRoute(ReportTable? matrix) {
    const columns = [
      'Starting point',
      'Destination / tourist spot',
      'Route records',
      'Lowest fare',
      'Highest fare',
      'Transportation types',
    ];
    if (matrix == null || matrix.isEmpty) {
      return const ReportTable(
        title: 'Fares by travel route',
        columns: columns,
        numericColumns: {2},
        rows: [],
      );
    }
    final startIdx = _col(matrix, 'Starting point');
    final destIdx = _col(matrix, 'Destination / tourist spot');
    final typeIdx = _col(matrix, 'Transportation type');
    final fareIdx = _col(matrix, 'Fare');
    final groups = <String, _RouteAgg>{};
    for (final row in matrix.rows) {
      final start = _cell(row, startIdx);
      final dest = _cell(row, destIdx);
      final key = '$start\u0000$dest';
      final agg = groups.putIfAbsent(
        key,
        () => _RouteAgg(start: start, destination: dest),
      );
      agg.records++;
      final type = _cell(row, typeIdx).trim();
      if (type.isNotEmpty) agg.types.add(type);
      agg.amounts.addAll(_pesoAmounts(_cell(row, fareIdx)));
    }
    final rows = groups.values.toList()
      ..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        return byStart != 0 ? byStart : a.destination.compareTo(b.destination);
      });
    return ReportTable(
      title: 'Fares by travel route',
      columns: columns,
      numericColumns: const {2},
      rows: [
        for (final r in rows)
          [
            r.start,
            r.destination,
            r.records.toString(),
            r.amounts.isEmpty ? '—' : formatPeso(r.amounts.reduce(_minInt)),
            r.amounts.isEmpty ? '—' : formatPeso(r.amounts.reduce(_maxInt)),
            r.types.isEmpty ? '—' : (r.types.toList()..sort()).join(', '),
          ],
      ],
    );
  }

  static int _minInt(int a, int b) => a < b ? a : b;
  static int _maxInt(int a, int b) => a > b ? a : b;

  static List<int> _pesoAmounts(String raw) {
    final out = <int>[];
    for (final match in RegExp(r'\d[\d,]*').allMatches(raw)) {
      final n = int.tryParse(match.group(0)!.replaceAll(',', ''));
      if (n != null) out.add(n);
    }
    return out;
  }

  static List<ReportMetric> metricsFor(
    DotFormCatalogEntry form,
    ReportDataset dataset,
    List<ReportTable> content,
  ) {
    final icon = iconFor(form.id);
    ReportTable? named(String title) {
      for (final t in content) {
        if (t.title == title) return t;
      }
      return null;
    }

    final events = _sourceTables(dataset, form)
        .cast<ReportTable?>()
        .firstWhere((t) => t?.title == 'Events', orElse: () => null);
    final announcements = _sourceTables(dataset, form)
        .cast<ReportTable?>()
        .firstWhere(
          (t) => t?.title == 'Public announcements',
          orElse: () => null,
        );

    int uniqueEvents() {
      if (events == null) return 0;
      final idx = _col(events, 'Event');
      final dateIdx = _col(events, 'Date & time');
      return {
        for (final row in events.rows) _eventIdentity(row, idx, dateIdx),
      }.length;
    }

    int statusCount(String status) {
      if (events == null) return 0;
      final idx = _col(events, 'Status');
      final eventIdx = _col(events, 'Event');
      final dateIdx = _col(events, 'Date & time');
      return {
        for (final row in events.rows)
          if (_cell(row, idx).toLowerCase() == status)
            _eventIdentity(row, eventIdx, dateIdx),
      }.length;
    }

    int categoryCount() {
      if (events == null) return 0;
      final idx = _col(events, 'Category');
      return {
        for (final row in events.rows) _cell(row, idx),
      }.length;
    }

    int lguCount() {
      if (events == null) return 0;
      final idx = _col(events, 'Municipality');
      return {
        for (final row in events.rows)
          for (final lgu in _splitLgus(_cell(row, idx)))
            if (lgu != '—') lgu,
      }.length;
    }

    int checkInSum() {
      if (events == null) return 0;
      final idx = _col(events, 'Check-ins that day');
      var sum = 0;
      for (final row in events.rows) {
        sum += _parseCount(_cell(row, idx));
      }
      return sum;
    }

    int listingCount() => named('Municipal event listings')?.rows.length ?? 0;

    switch (form.id) {
      case evt1Id:
        return [
          ReportMetric(
            label: 'Tourism events',
            value: formatCount(uniqueEvents()),
            icon: icon,
            caption: 'one row per event',
          ),
          ReportMetric(
            label: 'Upcoming',
            value: formatCount(statusCount('upcoming')),
            icon: icon,
            caption: 'scheduled after today',
          ),
          ReportMetric(
            label: 'Completed',
            value: formatCount(statusCount('completed')),
            icon: icon,
            caption: 'already held',
          ),
          ReportMetric(
            label: 'Categories',
            value: formatCount(categoryCount()),
            icon: icon,
          ),
          ReportMetric(
            label: 'Check-ins on event days',
            value: formatCount(checkInSum()),
            icon: icon,
            caption: 'tourist QR check-ins — not confirmed attendance',
          ),
        ];
      case evt2Id:
        final unique = uniqueEvents();
        final listings = listingCount();
        return [
          ReportMetric(
            label: 'Unique events',
            value: formatCount(unique),
            icon: icon,
            caption: listings > unique
                ? '$listings municipal listings because some events cover more than one LGU'
                : 'each event counted once',
          ),
          ReportMetric(
            label: 'Municipalities with events',
            value: formatCount(lguCount()),
            icon: icon,
          ),
          ReportMetric(
            label: 'Upcoming',
            value: formatCount(statusCount('upcoming')),
            icon: icon,
          ),
          ReportMetric(
            label: 'Completed',
            value: formatCount(statusCount('completed')),
            icon: icon,
          ),
        ];
      case evt3Id:
        return [
          ReportMetric(
            label: 'Unique events',
            value: formatCount(uniqueEvents()),
            icon: icon,
            caption: 'from the selected period',
          ),
          ReportMetric(
            label: 'Categories',
            value: formatCount(categoryCount()),
            icon: icon,
          ),
          ReportMetric(
            label: 'Upcoming',
            value: formatCount(statusCount('upcoming')),
            icon: icon,
          ),
          ReportMetric(
            label: 'Completed',
            value: formatCount(statusCount('completed')),
            icon: icon,
          ),
          ReportMetric(
            label: 'Municipalities with events',
            value: formatCount(lguCount()),
            icon: icon,
          ),
        ];
      case ann1Id:
        final n = announcements?.rows.length ?? 0;
        return [
          ReportMetric(
            label: 'Public announcements',
            value: formatCount(n),
            icon: icon,
            caption: 'in the selected period',
          ),
        ];
      case ann2Id:
        final munTable = named('Announcements by municipality');
        final n = munTable?.rows.fold<int>(
              0,
              (sum, row) => sum + _parseCount(row.length > 1 ? row[1] : '0'),
            ) ??
            0;
        final lguFilter = dataset.filters.effectiveMunicipality;
        return [
          ReportMetric(
            label: 'Announcements',
            value: formatCount(n),
            icon: icon,
            caption: lguFilter == null
                ? 'not tagged to a city or municipality in Firebase'
                : 'no LGU tag — cannot scope to $lguFilter',
          ),
        ];
      case ean1Id:
        return [
          ReportMetric(
            label: 'Tourism events',
            value: formatCount(uniqueEvents()),
            icon: icon,
            caption: 'event records in scope',
          ),
          ReportMetric(
            label: 'Public announcements',
            value: formatCount(announcements?.rows.length ?? 0),
            icon: icon,
            caption: 'announcement records in scope',
          ),
          ReportMetric(
            label: 'Upcoming events',
            value: formatCount(statusCount('upcoming')),
            icon: icon,
          ),
          ReportMetric(
            label: 'Completed events',
            value: formatCount(statusCount('completed')),
            icon: icon,
          ),
        ];
      case mfx1Id:
        return _fareMetrics(
          icon,
          named('Transportation fare matrix') ?? named('Fare matrix'),
          routesCaption: 'published matrix records',
        );
      case mfx2Id:
        final byMun = named('Fares by municipality');
        return [
          ReportMetric(
            label: 'Municipalities',
            value: formatCount(byMun?.rows.length ?? 0),
            icon: icon,
            caption: 'with at least one fare',
          ),
          ..._fareMetrics(
            icon,
            named('Municipal fare records') ?? named('Fare matrix'),
            routesCaption: 'fare records in municipal scope',
          ),
        ];
      case mfx3Id:
        final routes = named('Fares by travel route');
        return [
          ReportMetric(
            label: 'Travel routes',
            value: formatCount(routes?.rows.length ?? 0),
            icon: icon,
            caption: 'distinct starting point to destination pairs',
          ),
          ReportMetric(
            label: 'Route records',
            value: formatCount(
              routes?.rows.fold<int>(
                    0,
                    (sum, row) =>
                        sum + _parseCount(row.length > 2 ? row[2] : '0'),
                  ) ??
                  0,
            ),
            icon: icon,
            caption: 'published fare lines grouped into routes',
          ),
        ];
      case mfx4Id:
        return _fareMetrics(
          icon,
          named(kTerminalFaresTableTitle) ?? named(kTerminalFaresSourceTitle),
          routesCaption: 'inter-LGU terminal records',
        );
      case mfx5Id:
        return [
          ReportMetric(
            label: 'Municipalities',
            value: formatCount(named('Fares by municipality')?.rows.length ?? 0),
            icon: icon,
          ),
          ReportMetric(
            label: 'Travel routes',
            value: formatCount(named('Fares by travel route')?.rows.length ?? 0),
            icon: icon,
          ),
          ..._fareMetrics(
            icon,
            named('Provincial fare matrix') ?? named('Fare matrix'),
            routesCaption: 'all published fare records',
          ),
        ];
      default:
        return dataset.metrics;
    }
  }

  static List<ReportMetric> _fareMetrics(
    IconData icon,
    ReportTable? table, {
    required String routesCaption,
  }) {
    final fareIdx = table == null ? -1 : _col(table, 'Fare');
    final amounts = <int>[
      if (table != null)
        for (final row in table.rows) ..._pesoAmounts(_cell(row, fareIdx)),
    ];
    final n = table?.rows.length ?? 0;
    return [
      ReportMetric(
        label: 'Routes',
        value: formatCount(n),
        icon: icon,
        caption: routesCaption,
      ),
      ReportMetric(
        label: 'Lowest fare',
        value: amounts.isEmpty ? '—' : formatPeso(amounts.reduce(_minInt)),
        icon: icon,
        caption: amounts.isEmpty ? 'no fare amounts in scope' : 'from published records',
      ),
      ReportMetric(
        label: 'Highest fare',
        value: amounts.isEmpty ? '—' : formatPeso(amounts.reduce(_maxInt)),
        icon: icon,
        caption: amounts.isEmpty ? 'no fare amounts in scope' : 'from published records',
      ),
    ];
  }

  static List<String> _warningsFor(
    DotFormCatalogEntry form,
    ReportDataset dataset,
    List<ReportTable> content,
  ) {
    final notes = <String>[
      if (dataset.warning != null &&
          !(form.id == ann2Id &&
              dataset.warning!.contains('not narrowed by municipality')))
        dataset.warning!,
    ];
    final hasRows = content.any((t) => t.rows.isNotEmpty);
    if (!hasRows) {
      notes.add('No data available for this template and the selected filters.');
    }
    switch (form.id) {
      case evt1Id || evt2Id || evt3Id || ean1Id:
        notes.add(
          'Check-ins on event days are tourist QR check-ins in the event LGU on those dates, not confirmed event attendance.',
        );
      case ann1Id:
        notes.add(
          'Public announcements have no municipality field in Firebase.',
        );
      case ann2Id:
        final lgu = dataset.filters.effectiveMunicipality;
        notes.add(
          lgu == null
              ? 'Public announcements have no municipality field in Firebase, so they cannot be grouped by city. Rows are listed as province-wide.'
              : 'Public announcements have no municipality field in Firebase, so this municipal report has no LGU-tagged rows for $lgu.',
        );
      case mfx1Id || mfx2Id || mfx3Id || mfx4Id || mfx5Id:
        notes.add(
          'Matrix fares are the current published rates. The custom date range is stored on the export header and does not change fare amounts.',
        );
    }
    return notes;
  }

  static List<String>? footerFor(ReportTable table) {
    if (table.title == 'Summary statistics') return null;
    if (table.rows.isEmpty || table.numericColumns.isEmpty) return null;
    final sums = <int, int>{};
    for (final i in table.numericColumns) {
      var sum = 0;
      var any = false;
      for (final row in table.rows) {
        if (i >= row.length) continue;
        final n = int.tryParse(row[i].replaceAll(',', '').trim());
        if (n == null) continue;
        any = true;
        sum += n;
      }
      if (any) sums[i] = sum;
    }
    if (sums.isEmpty) return null;
    return [
      for (var c = 0; c < table.columns.length; c++)
        c == 0
            ? 'Total'
            : sums.containsKey(c)
                ? sums[c]!.toString()
                : '',
    ];
  }

  static List<DotReportPreviewTable> previewTables(
    ReportDataset dataset, {
    bool matrixFares = false,
    DotFormCatalogEntry? form,
  }) {
    final tables = dataset.tables;
    final gaps = <String>[
      if (dataset.warning != null) dataset.warning!,
      if (matrixFares &&
          (dataset.warning == null ||
              !dataset.warning!.contains('published rates')))
        'Matrix fares are the current published rates. The custom date range is stored on the export header and does not change fare amounts.',
    ];
    if (tables.isEmpty) {
      return [
        DotReportPreviewTable(
          title: dataset.title,
          headers: const ['Record'],
          rows: const [],
          summaryLine: '${dataset.title} · ${dataset.periodLabel} · 0 rows',
          gaps: gaps,
        ),
      ];
    }
    final dataRows = tables
        .where((t) => t.title != 'Summary statistics')
        .fold<int>(0, (n, t) => n + t.rows.length);
    final summary =
        '${dataset.title} · ${dataset.periodLabel} · $dataRows row${dataRows == 1 ? '' : 's'}';
    return [
      for (final t in tables)
        DotReportPreviewTable(
          title: t.title,
          headers: t.columns,
          rows: t.rows,
          footer: footerFor(t),
          summaryLine: summary,
          gaps: gaps,
        ),
    ];
  }
}

class _RouteAgg {
  _RouteAgg({required this.start, required this.destination});

  final String start;
  final String destination;
  int records = 0;
  final Set<String> types = {};
  final List<int> amounts = [];
}
