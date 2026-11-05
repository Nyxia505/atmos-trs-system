import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/dot_report_entity_scope.dart';
import 'package:atmos_trs_system/utils/portal_summary_dot_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/services/reports/report_models.dart';

void main() {
  group('PortalSummaryDotReport catalog', () {
    test('events category lists the EVT / ANN / EAN templates', () {
      final forms = PortalSummaryDotReport.formsFor(
        DotReportEntityKind.eventsAnnouncements,
      );
      expect(
        forms.map((f) => f.title).toList(),
        [
          'EVT 1 — Tourism Events Record',
          'EVT 2 — Municipal Events Report',
          'EVT 3 — Tourism Events Summary',
          'ANN 1 — Public Announcements Record',
          'ANN 2 — Municipal Announcements Report',
          'EAN 1 — Events & Announcements Summary',
        ],
      );
      expect(forms.map((f) => f.code).toList(), [
        'EVT 1',
        'EVT 2',
        'EVT 3',
        'ANN 1',
        'ANN 2',
        'EAN 1',
      ]);
      expect(forms.every((f) => f.matchesSearch('events') || f.matchesSearch('announcements')), isTrue);
      expect(forms.every((f) => !f.offersOfficialBlankSecondary), isTrue);
      expect(
        PortalSummaryDotReport.iconFor(PortalSummaryDotReport.evt1Id),
        Icons.event_note_outlined,
      );
      expect(
        PortalSummaryDotReport.iconFor(PortalSummaryDotReport.ann1Id),
        Icons.campaign_outlined,
      );
      expect(
        forms.first.menuDescription,
        'OPTACA · Scheduled tourism events and activities.',
      );
    });

    test('VAR menu description stays family and fill mode', () {
      final var2 = kDotFormCatalog.firstWhere((f) => f.id == 'var2');
      expect(var2.menuDescription, 'Attraction (VAR) · ATMOS fill');
      expect(
        PortalSummaryDotReport.iconFor(var2.id),
        Icons.auto_awesome_outlined,
      );
    });

    test('matrix category lists the MFX templates', () {
      final forms = PortalSummaryDotReport.formsFor(
        DotReportEntityKind.matrixFares,
      );
      expect(
        forms.map((f) => f.code).toList(),
        ['MFX 1', 'MFX 2', 'MFX 3', 'MFX 4', 'MFX 5'],
      );
      expect(
        forms.map((f) => f.title).toList(),
        [
          'MFX 1 — Transportation Fare Matrix',
          'MFX 2 — Municipal Fare Matrix',
          'MFX 3 — Route Fare Summary',
          'MFX 4 — Terminal-to-Terminal Fare Report',
          'MFX 5 — Provincial Fare Matrix',
        ],
      );
      expect(forms.any((f) => f.matchesSearch('jeepney')), isTrue);
      expect(
        PortalSummaryDotReport.iconFor(PortalSummaryDotReport.mfx4Id),
        Icons.route_outlined,
      );
    });
  });

  group('PortalSummaryDotReport.applyForm', () {
    ReportDataset dataset() {
      return ReportDataset(
        kind: ReportKind.eventsAnnouncements,
        generatedAt: DateTime(2026, 10, 27),
        filters: ReportFilters.none,
        periodLabel: 'October 2026',
        metrics: const [],
        charts: const [],
        tables: const [
          ReportTable(
            title: 'Events',
            columns: ['Event', 'Venue'],
            rows: [
              ['Fiesta', 'Plaza'],
            ],
          ),
          ReportTable(
            title: 'Public announcements',
            columns: ['Announcement'],
            rows: [
              ['Holiday notice'],
            ],
          ),
        ],
      );
    }

    test('EVT 1 keeps the Events table and template title', () {
      final form = PortalSummaryDotReport.eventsForms.firstWhere(
        (f) => f.id == PortalSummaryDotReport.evt1Id,
      );
      final next = PortalSummaryDotReport.applyForm(dataset(), form);
      expect(next.tables.map((t) => t.title), [
        'Summary statistics',
        'Tourism event records',
      ]);
      expect(next.tables.last.rows, [
        ['Fiesta', 'Plaza'],
      ]);
      expect(next.title, 'EVT 1 — Tourism Events Record');
      expect(
        next.filterSummary,
        [
          ('Template', 'EVT 1'),
          ('Form type', 'EVT 1 — Tourism Events Record'),
        ],
      );
      expect(
        next.metrics.map((m) => m.label),
        isNot(contains('Public announcements')),
      );
    });

    test('EAN 1 is a combined summary with separate event and announcement totals', () {
      final form = PortalSummaryDotReport.eventsForms.firstWhere(
        (f) => f.id == PortalSummaryDotReport.ean1Id,
      );
      final next = PortalSummaryDotReport.applyForm(dataset(), form);
      expect(next.tables.map((t) => t.title), [
        'Summary statistics',
        'Events by category',
        'Events by municipality',
        'Tourism event records',
        'Public announcement records',
      ]);
      expect(
        next.tables
            .firstWhere((t) => t.title == 'Tourism event records')
            .rows
            .map((r) => r.first),
        ['Fiesta'],
      );
      expect(
        next.tables
            .firstWhere((t) => t.title == 'Public announcement records')
            .rows
            .map((r) => r.first),
        ['Holiday notice'],
      );
      expect(next.title, 'EAN 1 — Events & Announcements Summary');
      expect(
        next.metrics.map((m) => m.label),
        containsAll(['Tourism events', 'Public announcements']),
      );
    });

    test('ANN 1 keeps announcements only', () {
      final form = PortalSummaryDotReport.eventsForms.firstWhere(
        (f) => f.id == PortalSummaryDotReport.ann1Id,
      );
      final next = PortalSummaryDotReport.applyForm(dataset(), form);
      expect(next.tables.map((t) => t.title), [
        'Summary statistics',
        'Public announcement records',
      ]);
      expect(next.metrics.single.label, 'Public announcements');
    });

    test('EVT 2 / EVT 3 layout add summary sections from the same rows', () {
      final rich = ReportDataset(
        kind: ReportKind.eventsAnnouncements,
        generatedAt: DateTime(2026, 10, 27),
        filters: ReportFilters.none,
        periodLabel: 'October 2026',
        metrics: const [],
        charts: const [],
        tables: const [
          ReportTable(
            title: 'Events',
            columns: [
              'Event',
              'Category',
              'Municipality',
              'Venue',
              'Date & time',
              'Status',
              'Check-ins that day',
            ],
            numericColumns: {6},
            rows: [
              [
                'Charter Day',
                'Festival',
                'Oroquieta City; Jimenez',
                'Capitol',
                '08 Oct 2026, 08:00 AM',
                'Upcoming',
                '12',
              ],
              [
                'Heritage Walk',
                'Tour',
                'Jimenez',
                'Church',
                '12 Oct 2026, 03:00 PM',
                'Completed',
                '4',
              ],
            ],
          ),
        ],
      );
      final evt2 = PortalSummaryDotReport.eventsForms.firstWhere(
        (f) => f.id == PortalSummaryDotReport.evt2Id,
      );
      final evt2Tables = PortalSummaryDotReport.layoutTables(rich, evt2);
      expect(
        evt2Tables.map((t) => t.title),
        ['Events by municipality', 'Municipal event listings'],
      );
      expect(evt2Tables.first.rows, containsAll([
        ['Oroquieta City', '1', '1', '0'],
        ['Jimenez', '2', '1', '1'],
      ]));
      expect(evt2Tables.last.rows.length, 3);
      final evt2Applied = PortalSummaryDotReport.applyForm(rich, evt2);
      expect(
        evt2Applied.metrics.firstWhere((m) => m.label == 'Unique events').value,
        '2',
      );

      final evt3 = PortalSummaryDotReport.eventsForms.firstWhere(
        (f) => f.id == PortalSummaryDotReport.evt3Id,
      );
      expect(
        PortalSummaryDotReport.layoutTables(rich, evt3).map((t) => t.title),
        [
          'Events by category',
          'Events by status',
          'Events by municipality',
          'Events by month',
        ],
      );
    });

    test('same event title on different days counts as two unique events', () {
      final form = PortalSummaryDotReport.eventsForms.firstWhere(
        (f) => f.id == PortalSummaryDotReport.evt3Id,
      );
      final dataset = ReportDataset(
        kind: ReportKind.eventsAnnouncements,
        generatedAt: DateTime(2026, 10, 27),
        filters: ReportFilters.none,
        periodLabel: 'October 2026',
        metrics: const [],
        charts: const [],
        tables: const [
          ReportTable(
            title: 'Events',
            columns: [
              'Event',
              'Category',
              'Municipality',
              'Venue',
              'Date & time',
              'Status',
              'Check-ins that day',
            ],
            rows: [
              [
                'Fiesta',
                'Festival',
                'Jimenez',
                'Plaza',
                '08 Oct 2026, 08:00 AM',
                'Upcoming',
                '1',
              ],
              [
                'Fiesta',
                'Festival',
                'Jimenez',
                'Plaza',
                '15 Oct 2026, 08:00 AM',
                'Upcoming',
                '2',
              ],
            ],
          ),
        ],
      );
      final next = PortalSummaryDotReport.applyForm(dataset, form);
      expect(
        next.metrics.firstWhere((m) => m.label == 'Unique events').value,
        '2',
      );
      final byMonth = next.tables.firstWhere((t) => t.title == 'Events by month');
      expect(byMonth.rows.single[1], '2');
    });

    test('MFX 4 maps to terminal-to-terminal fares', () {
      expect(
        PortalSummaryDotReport.tableTitlesFor(PortalSummaryDotReport.mfx4Id),
        {PortalSummaryDotReport.kTerminalFaresSourceTitle},
      );
    });

    test('MFX 3 groups the fare matrix by travel route', () {
      expect(
        PortalSummaryDotReport.tableTitlesFor(PortalSummaryDotReport.mfx3Id),
        {'Fare matrix'},
      );
    });

    test('each template produces a distinct section set', () {
      final events = dataset();
      final titles = <String, List<String>>{};
      for (final form in PortalSummaryDotReport.eventsForms) {
        titles[form.code] = PortalSummaryDotReport.applyForm(events, form)
            .tables
            .map((t) => t.title)
            .toList();
      }
      expect(titles['EVT 1'], isNot(titles['EVT 2']));
      expect(titles['EVT 2'], isNot(titles['EVT 3']));
      expect(titles['EVT 2'], isNot(titles['EAN 1']));
      expect(titles['ANN 1'], isNot(titles['ANN 2']));
      expect(titles['EVT 1'], isNot(contains('Public announcement records')));
      expect(titles['ANN 1'], isNot(contains('Tourism event records')));
    });

    test('matrix dates are not applied to filters', () {
      final filters = PortalSummaryDotReport.filters(
        kind: DotReportEntityKind.matrixFares,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 27),
        municipalityName: 'Ozamiz City',
      );
      expect(filters.dateRange, isNull);
      expect(filters.effectiveMunicipality, 'Ozamiz City');
    });

    test('Ozamis spelling resolves to the catalog Ozamiz City', () {
      final filters = PortalSummaryDotReport.filters(
        kind: DotReportEntityKind.eventsAnnouncements,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 27),
        municipalityName: 'Ozamis City',
      );
      expect(filters.effectiveMunicipality, 'Ozamiz City');
    });

    test('events dates are applied inclusively', () {
      final filters = PortalSummaryDotReport.filters(
        kind: DotReportEntityKind.eventsAnnouncements,
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 27),
        municipalityName: '',
      );
      expect(filters.dateRange, isNotNull);
      expect(filters.includesDate(DateTime(2026, 10, 1)), isTrue);
      expect(filters.includesDate(DateTime(2026, 10, 27)), isTrue);
      expect(filters.includesDate(DateTime(2026, 9, 30)), isFalse);
    });

    test('events dates may start in the future', () {
      final filters = PortalSummaryDotReport.filters(
        kind: DotReportEntityKind.eventsAnnouncements,
        start: DateTime(2027, 1, 1),
        end: DateTime(2027, 12, 31),
        municipalityName: '',
      );
      expect(filters.dateRange, isNotNull);
      expect(filters.includesDate(DateTime(2027, 6, 1)), isTrue);
    });
  });
}
