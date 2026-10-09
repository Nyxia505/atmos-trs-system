import 'package:flutter/material.dart';

/// Shapes shared by the Reports page, the report preview, and the exporters, so
/// a downloaded file always contains exactly what the screen showed.

/// The four reports offered on the admin Reports page.
enum ReportKind {
  touristArrivals,
  spotPerformance,
  eventsAnnouncements,
  matrixFares,
}

extension ReportKindInfo on ReportKind {
  String get title => switch (this) {
    ReportKind.touristArrivals => 'Tourist Arrivals Summary',
    ReportKind.spotPerformance => 'Spot Performance',
    ReportKind.eventsAnnouncements => 'Events & Announcements',
    ReportKind.matrixFares => 'Matrix Fares',
  };

  String get subtitle => switch (this) {
    ReportKind.touristArrivals => 'Monthly headcount and LGU breakdown',
    ReportKind.spotPerformance => 'Ratings, visits, and top lists',
    ReportKind.eventsAnnouncements => 'Scheduled events and public notices',
    ReportKind.matrixFares =>
      'Municipality transport fees and hub ↔ tourist spot fares',
  };

  IconData get icon => switch (this) {
    ReportKind.touristArrivals => Icons.groups_outlined,
    ReportKind.spotPerformance => Icons.place_outlined,
    ReportKind.eventsAnnouncements => Icons.event_note_outlined,
    ReportKind.matrixFares => Icons.grid_on_outlined,
  };

  /// Stem of the download filename, e.g. `tourist_arrivals_summary`.
  String get fileStem => switch (this) {
    ReportKind.touristArrivals => 'tourist_arrivals_summary',
    ReportKind.spotPerformance => 'spot_performance',
    ReportKind.eventsAnnouncements => 'events_announcements',
    ReportKind.matrixFares => 'matrix_fares',
  };

  /// Which filters apply, so the UI only offers ones that do something.
  Set<ReportFilterField> get supportedFilters => switch (this) {
    ReportKind.touristArrivals => {
      ReportFilterField.dateRange,
      ReportFilterField.municipality,
    },
    ReportKind.spotPerformance => {
      ReportFilterField.dateRange,
      ReportFilterField.municipality,
      ReportFilterField.touristSpot,
    },
    ReportKind.eventsAnnouncements => {
      ReportFilterField.dateRange,
      ReportFilterField.municipality,
      ReportFilterField.event,
    },
    ReportKind.matrixFares => {
      ReportFilterField.municipality,
      ReportFilterField.touristSpot,
      ReportFilterField.transportType,
    },
  };
}

enum ReportFilterField {
  dateRange,
  municipality,
  touristSpot,
  event,
  transportType,
}

/// Whether the report covers every LGU or a single municipality.
enum ReportScope {
  overall,
  singleMunicipality,
}

/// Wording for a report covering every LGU rather than a single one.
const String kOverallScopeLabel = 'Overall — all municipalities';

/// Report title including the LGU scope, e.g. `Spot Performance — Sagada`.
String reportTitleFor(ReportKind kind, String? municipality) =>
    municipality == null || municipality.trim().isEmpty
        ? kind.title
        : '${kind.title} — $municipality';

enum ReportFormat { pdf, csv, xlsx }

extension ReportFormatInfo on ReportFormat {
  String get label => switch (this) {
    ReportFormat.pdf => 'PDF',
    ReportFormat.csv => 'CSV',
    ReportFormat.xlsx => 'Excel (XLSX)',
  };

  String get extension => switch (this) {
    ReportFormat.pdf => 'pdf',
    ReportFormat.csv => 'csv',
    ReportFormat.xlsx => 'xlsx',
  };

  String get mimeType => switch (this) {
    ReportFormat.pdf => 'application/pdf',
    ReportFormat.csv => 'text/csv',
    ReportFormat.xlsx =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };

  IconData get icon => switch (this) {
    ReportFormat.pdf => Icons.picture_as_pdf_outlined,
    ReportFormat.csv => Icons.table_rows_outlined,
    ReportFormat.xlsx => Icons.grid_on_outlined,
  };

  String get description => switch (this) {
    ReportFormat.pdf => 'Formatted document with summary and tables',
    ReportFormat.csv => 'Plain rows for spreadsheets and data tools',
    ReportFormat.xlsx => 'Workbook with one sheet per table',
  };
}

/// Selected report filters. Unset fields mean "everything".
@immutable
class ReportFilters {
  /// Overall (all LGUs) versus a single municipality selection.
  final ReportScope scope;

  final DateTimeRange? dateRange;

  /// [Municipality.name], or null when [scope] is [ReportScope.overall] or
  /// when single-municipality mode still needs an LGU chosen.
  final String? municipality;

  /// [TouristSpot.name], or null for all spots.
  final String? touristSpot;

  /// [TourismEvent.id], or null for all events.
  final String? eventId;

  /// Fare `routeType` (jeepney / bus / provincial / tricycle), or null for all.
  final String? transportType;

  const ReportFilters({
    this.scope = ReportScope.overall,
    this.dateRange,
    this.municipality,
    this.touristSpot,
    this.eventId,
    this.transportType,
  });

  static const ReportFilters none = ReportFilters();

  /// True when the report covers every LGU instead of a single one.
  bool get isOverall => scope == ReportScope.overall;

  /// True when Single Municipality is chosen but no LGU has been picked yet.
  bool get needsMunicipalitySelection =>
      scope == ReportScope.singleMunicipality &&
      (municipality == null || municipality!.trim().isEmpty);

  /// Active LGU name when single-municipality scope is fully chosen.
  String? get effectiveMunicipality =>
      needsMunicipalitySelection || isOverall ? null : municipality?.trim();

  /// `Overall — all municipalities`, or the chosen LGU name.
  String get scopeLabel {
    if (isOverall) return kOverallScopeLabel;
    final lgu = municipality?.trim();
    if (lgu == null || lgu.isEmpty) return 'Single municipality — choose an LGU';
    return lgu;
  }

  bool get isEmpty =>
      scope == ReportScope.overall &&
      dateRange == null &&
      municipality == null &&
      touristSpot == null &&
      eventId == null &&
      transportType == null;

  ReportFilters copyWith({
    ReportScope? scope,
    DateTimeRange? dateRange,
    String? municipality,
    String? touristSpot,
    String? eventId,
    String? transportType,
    bool clearDateRange = false,
    bool clearMunicipality = false,
    bool clearTouristSpot = false,
    bool clearEvent = false,
    bool clearTransportType = false,
  }) {
    final nextScope = scope ?? this.scope;
    final nextMunicipality = clearMunicipality
        ? null
        : (municipality ?? this.municipality);
    return ReportFilters(
      scope: nextScope,
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      municipality: nextScope == ReportScope.overall ? null : nextMunicipality,
      touristSpot: clearTouristSpot ? null : (touristSpot ?? this.touristSpot),
      eventId: clearEvent ? null : (eventId ?? this.eventId),
      transportType: clearTransportType
          ? null
          : (transportType ?? this.transportType),
    );
  }

  /// True when [at] falls inside [dateRange] (inclusive of both end days).
  bool includesDate(DateTime? at) {
    final range = dateRange;
    if (range == null) return true;
    if (at == null) return false;
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
    ).add(const Duration(days: 1));
    return !at.isBefore(start) && at.isBefore(end);
  }

  @override
  bool operator ==(Object other) =>
      other is ReportFilters &&
      other.scope == scope &&
      other.dateRange == dateRange &&
      other.municipality == municipality &&
      other.touristSpot == touristSpot &&
      other.eventId == eventId &&
      other.transportType == transportType;

  @override
  int get hashCode => Object.hash(
        scope,
        dateRange,
        municipality,
        touristSpot,
        eventId,
        transportType,
      );
}

/// One headline number, e.g. "Total Arrivals — 1,204".
@immutable
class ReportMetric {
  final String label;
  final String value;

  /// Extra context shown under the value, e.g. "vs previous period".
  final String? caption;
  final IconData icon;

  const ReportMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
  });
}

enum ReportChartType { line, bar, donut }

/// A chart described as data, so the page and the preview render it the same way
/// and the exporters can fall back to the underlying table.
@immutable
class ReportChart {
  final String title;
  final ReportChartType type;
  final List<String> labels;
  final List<double> values;

  /// Unit suffix for tooltips, e.g. `arrival(s)` or `PHP`.
  final String valueSuffix;

  const ReportChart({
    required this.title,
    required this.type,
    required this.labels,
    required this.values,
    this.valueSuffix = '',
  });

  bool get hasData => values.any((v) => v > 0);
}

/// A detailed data table. [rows] are pre-formatted so every export format and
/// the on-screen table show identical text.
@immutable
class ReportTable {
  final String title;
  final List<String> columns;
  final List<List<String>> rows;

  /// Columns holding numbers, so XLSX writes them as numeric cells and the UI
  /// can right-align them.
  final Set<int> numericColumns;

  const ReportTable({
    required this.title,
    required this.columns,
    required this.rows,
    this.numericColumns = const {},
  });

  bool get isEmpty => rows.isEmpty;
}

/// Everything one report shows: headline numbers, charts, and detail tables.
@immutable
class ReportDataset {
  final ReportKind kind;
  final DateTime generatedAt;
  final ReportFilters filters;

  /// Human-readable period, e.g. "January 2026 – September 2026".
  final String periodLabel;
  final List<ReportMetric> metrics;
  final List<ReportChart> charts;
  final List<ReportTable> tables;

  /// Active filters as label/value pairs, resolved to display names by the
  /// service. Rendered in the preview and in every export header.
  final List<(String, String)> filterSummary;

  /// Set when the underlying data could not be read in full, so the UI can warn
  /// without pretending the numbers are complete.
  final String? warning;

  const ReportDataset({
    required this.kind,
    required this.generatedAt,
    required this.filters,
    required this.periodLabel,
    required this.metrics,
    required this.charts,
    required this.tables,
    this.filterSummary = const [],
    this.warning,
  });

  /// Includes the LGU scope, so a single-municipality download is never
  /// mistaken for the province-wide one.
  String get title => reportTitleFor(kind, filters.effectiveMunicipality);

  /// True when no detail row survived the filters — the "no results" case.
  bool get hasNoRows => tables.every((t) => t.isEmpty);
}
