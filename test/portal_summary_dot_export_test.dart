import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/utils/dot_report_pdf_export.dart';
import 'package:atmos_trs_system/utils/dot_report_preview.dart';
import 'package:atmos_trs_system/utils/portal_summary_dot_export.dart';
import 'package:atmos_trs_system/utils/portal_summary_dot_report.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/services/reports/report_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory outDir;

  setUpAll(() {
    outDir = Directory('build/portal_summary_export_check')
      ..createSync(recursive: true);
  });

  group('PortalSummaryDotExport', () {
    test('EVT 1 Excel uses DOT header styling and readable columns', () {
      final form = _form(PortalSummaryDotReport.evt1Id);
      final dataset = PortalSummaryDotReport.applyForm(_eventsDataset(), form);
      final bytes = PortalSummaryDotExport.buildXlsx(
        form: form,
        dataset: dataset,
        scopeLabel: 'Misamis Occidental',
      );
      expect(bytes.take(2).toList(), [0x50, 0x4B]);
      File('${outDir.path}/EVT1.xlsx').writeAsBytesSync(bytes);

      final book = Excel.decodeBytes(bytes);
      expect(
        book.tables.keys,
        containsAll(['EVT 1', 'Summary statistics', 'Tourism event records']),
      );

      final cover = book['EVT 1'];
      expect(_cellText(cover, 0, 0), contains('ATMOS TRS'));
      expect(_cellText(cover, 1, 0), 'EVT 1 — Tourism Events Record');
      expect(cover.getColumnWidths[1]!, greaterThanOrEqualTo(44));

      final events = book['Tourism event records'];
      expect(events.headerFooter?.oddFooter, contains('ATMOS TRS'));
      expect(events.getColumnWidths[0]!, greaterThanOrEqualTo(14));
      final headerRow = _findRow(events, 'Event');
      expect(headerRow, isNotNull);
      expect(_cellText(events, headerRow!, 0), 'Event');
      expect(
        _cellText(events, headerRow + 1, 0),
        contains('Misamis Occidental Charter Day'),
      );
      expect(_cellText(events, headerRow + 1, 2), 'Oroquieta City');
    });

    test('EVT 1 Excel shows every tourism event record in Microsoft Excel XML',
        () {
      final form = _form(PortalSummaryDotReport.evt1Id);
      final dataset =
          PortalSummaryDotReport.applyForm(_nineEventsDataset(), form);
      final preview = PortalSummaryDotReport.previewTables(
        dataset,
        form: form,
      ).firstWhere((t) => t.title == 'Tourism event records');
      expect(preview.headers, [
        'Event',
        'Category',
        'Municipality',
        'Venue',
        'Date & time',
        'Status',
        'Check-ins that day',
      ]);
      expect(preview.rows, hasLength(9));
      expect(preview.footer, isNotNull);
      expect(preview.footer!.last, '185');

      final bytes = PortalSummaryDotExport.buildXlsx(
        form: form,
        dataset: dataset,
        scopeLabel: 'Misamis Occidental',
      );
      File('${outDir.path}/EVT1_nine_events.xlsx').writeAsBytesSync(bytes);
      File('${outDir.path}/EVT1.xlsx').writeAsBytesSync(bytes);

      final book = Excel.decodeBytes(bytes);
      expect(
        book.tables.keys,
        containsAll(['EVT 1', 'Summary statistics', 'Tourism event records']),
      );
      final eventsTable = dataset.tables.firstWhere(
        (t) => t.title == 'Tourism event records',
      );
      final cover = book['EVT 1'];
      expect(_excelRecordCount(cover, eventsTable), 9);
      expect(_findRow(cover, 'TOURISM EVENT RECORDS'), isNotNull);
      expect(_cellText(cover, _findRow(cover, 'Total')!, 6), '185');
      for (final row in preview.rows) {
        expect(_columnValues(cover, 0), contains(row.first));
      }

      final sheet = book['Tourism event records'];
      expect(_excelRecordCount(sheet, eventsTable), 9);
      expect(_cellText(sheet, _findRow(sheet, 'Event')!, 0), 'Event');
      expect(_cellText(sheet, _findRow(sheet, 'Event')!, 1), 'Category');
      expect(_cellText(sheet, _findRow(sheet, 'Event')!, 2), 'Municipality');
      expect(_cellText(sheet, _findRow(sheet, 'Event')!, 3), 'Venue');
      expect(_cellText(sheet, _findRow(sheet, 'Event')!, 4), 'Date & time');
      expect(_cellText(sheet, _findRow(sheet, 'Event')!, 5), 'Status');
      expect(
        _cellText(sheet, _findRow(sheet, 'Event')!, 6),
        'Check-ins that day',
      );
      for (final row in preview.rows) {
        expect(_columnValues(sheet, 0), contains(row.first));
      }
      final totalRow = _findRow(sheet, 'Total');
      expect(totalRow, isNotNull);
      expect(_cellText(sheet, totalRow!, 6), '185');

      final archive = ZipDecoder().decodeBytes(bytes);
      expect(
        archive.files.any(
          (f) => f.name.replaceAll('\\', '/').contains('drawings/drawing'),
        ),
        isFalse,
      );
      for (final file in archive.files) {
        final name = file.name.replaceAll('\\', '/');
        if (!name.startsWith('xl/worksheets/sheet') ||
            !name.endsWith('.xml') ||
            name.contains('_rels')) {
          continue;
        }
        final xml = utf8.decode(file.content as List<int>);
        expect(
          xml,
          isNot(contains('<dimension ref="A1"/>')),
          reason: '$name must expose the full used range to Microsoft Excel',
        );
        expect(
          xml,
          contains(RegExp(r'<dimension ref="A1:[A-Z]+[0-9]+"/>')),
        );
      }
    });

    test('EVT 3 Excel is a summary workbook, not a generic dump', () {
      final form = _form(PortalSummaryDotReport.evt3Id);
      final dataset = PortalSummaryDotReport.applyForm(_eventsDataset(), form);
      final bytes = PortalSummaryDotExport.buildXlsx(
        form: form,
        dataset: dataset,
        scopeLabel: 'Misamis Occidental',
      );
      File('${outDir.path}/EVT3.xlsx').writeAsBytesSync(bytes);
      final book = Excel.decodeBytes(bytes);
      expect(
        book.tables.keys,
        containsAll([
          'EVT 3',
          'Summary statistics',
          'Events by category',
          'Events by status',
          'Events by municipality',
          'Events by month',
        ]),
      );
      expect(book.tables.keys, isNot(contains('Events')));
      expect(book.tables.keys, isNot(contains('Public announcements')));
    });

    test('EVT 1 Excel keeps full municipality text', () {
      final form = _form(PortalSummaryDotReport.evt1Id);
      final raw = _eventsDataset();
      final events = raw.tables.firstWhere((t) => t.title == 'Events');
      final long = ReportTable(
        title: events.title,
        columns: events.columns,
        numericColumns: events.numericColumns,
        rows: [
          [
            'Perangat Festival',
            'Community',
            'Oroquieta City (Provincial Capitol Grounds)',
            'balay',
            'Oct 16, 2026, 12:52 AM',
            'Completed',
            '1',
          ],
          ...events.rows,
        ],
      );
      final dataset = PortalSummaryDotReport.applyForm(
        raw.withTables([
          long,
          ...raw.tables.where((t) => t.title != 'Events'),
        ]),
        form,
      );
      final preview = PortalSummaryDotReport.previewTables(
        dataset,
        form: form,
      ).firstWhere((t) => t.title == 'Tourism event records');
      expect(
        preview.rows.map((r) => r[2]),
        contains('Oroquieta City (Provincial Capitol Grounds)'),
      );

      final bytes = PortalSummaryDotExport.buildXlsx(
        form: form,
        dataset: dataset,
        scopeLabel: 'Oroquieta City',
      );
      File('${outDir.path}/EVT1_long_municipality.xlsx').writeAsBytesSync(bytes);
      final book = Excel.decodeBytes(bytes);
      expect(book.tables.keys, contains('Tourism event records'));
      final sheet = book['Tourism event records'];
      final munCol = _findColumn(sheet, 'Municipality');
      expect(munCol, isNotNull);
      expect(
        _columnValues(sheet, munCol!),
        contains('Oroquieta City (Provincial Capitol Grounds)'),
      );
      expect(_columnValues(sheet, 0), contains('Perangat Festival'));
    });

    test('ANN 1 Excel keeps public announcement records', () {
      final form = _form(PortalSummaryDotReport.ann1Id);
      final dataset = PortalSummaryDotReport.applyForm(_eventsDataset(), form);
      final preview = PortalSummaryDotReport.previewTables(
        dataset,
        form: form,
      ).firstWhere((t) => t.title == 'Public announcement records');
      expect(preview.rows, isNotEmpty);

      final bytes = PortalSummaryDotExport.buildXlsx(
        form: form,
        dataset: dataset,
        scopeLabel: 'Misamis Occidental',
      );
      File('${outDir.path}/ANN1.xlsx').writeAsBytesSync(bytes);
      final book = Excel.decodeBytes(bytes);
      expect(book.tables.keys, contains('Public announcement records'));
      final sheet = book['Public announcement records'];
      expect(
        _columnValues(sheet, _findColumn(sheet, 'Announcement')!),
        contains('Port schedule advisory for the long weekend'),
      );
    });

    test('ANN 2 Excel uses municipal announcements section', () {
      final form = _form(PortalSummaryDotReport.ann2Id);
      final dataset = PortalSummaryDotReport.applyForm(_eventsDataset(), form);
      final bytes = PortalSummaryDotExport.buildXlsx(
        form: form,
        dataset: dataset,
        scopeLabel: 'Oroquieta City',
      );
      File('${outDir.path}/ANN2.xlsx').writeAsBytesSync(bytes);
      final book = Excel.decodeBytes(bytes);
      expect(book.tables.keys, contains('Municipal announcements'));
      expect(book.tables.keys, isNot(contains('Events')));
    });

    test('MFX 4 Excel and PDF keep the terminal-to-terminal table', () async {
      final form = _form(PortalSummaryDotReport.mfx4Id);
      final dataset = PortalSummaryDotReport.applyForm(_matrixDataset(), form);
      final preview = PortalSummaryDotReport.previewTables(
        dataset,
        form: form,
        matrixFares: true,
      );
      final farePreview = preview.firstWhere(
        (t) => t.title == PortalSummaryDotReport.kTerminalFaresTableTitle,
      );
      expect(
        farePreview.headers,
        [
          'Municipality',
          'Starting point',
          'Destination / tourist spot',
          'Transportation type',
          'Fare',
          'Distance',
          'Estimated travel time',
        ],
      );
      expect(farePreview.rows, hasLength(1));
      expect(farePreview.rows.first[2], contains('Pipe Organ Church, Jimenez'));
      expect(
        dataset.metrics.firstWhere((m) => m.label == 'Routes').value,
        '1',
      );

      final bytes = PortalSummaryDotExport.buildXlsx(
        form: form,
        dataset: dataset,
        scopeLabel: 'Misamis Occidental',
      );
      File('${outDir.path}/MFX4.xlsx').writeAsBytesSync(bytes);
      final book = Excel.decodeBytes(bytes);
      expect(
        book.tables.keys,
        contains(PortalSummaryDotReport.kTerminalFaresTableTitle),
      );
      final sheet = book[PortalSummaryDotReport.kTerminalFaresTableTitle];
      final destCol = _findColumn(sheet, 'Destination / tourist spot');
      expect(destCol, isNotNull);
      expect(
        _columnValues(sheet, destCol!),
        contains('Pipe Organ Church, Jimenez'),
      );
      expect(_columnValues(sheet, destCol), hasLength(greaterThan(farePreview.rows.length)));
      expect(
        _columnValues(sheet, destCol)
            .where((v) => v == 'Pipe Organ Church, Jimenez'),
        hasLength(farePreview.rows.length),
      );

      final pdf = await PortalSummaryDotExport.buildPdf(
        form: form,
        dataset: dataset,
        scopeLabel: 'Misamis Occidental',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 27),
      );
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      File('${outDir.path}/MFX4.pdf').writeAsBytesSync(pdf);
      expect(pdf.length, greaterThan(5000));
      expect(_pdfPageCount(pdf), greaterThanOrEqualTo(1));
    });

    test('MFX 4 PDF keeps every terminal-to-terminal row across pages', () async {
      final form = _form(PortalSummaryDotReport.mfx4Id);
      final many = _matrixDataset(
        extraTerminalRows: [
          for (var i = 0; i < 40; i++)
            [
              'Oroquieta City',
              'Integrated Terminal',
              'Spot ${i + 1} with a long destination name for wrapping',
              'Bus',
              'PHP ${20 + i}',
              '${(i + 1) * 1.5} km',
              '${10 + i} min',
            ],
        ],
      );
      final dataset = PortalSummaryDotReport.applyForm(many, form);
      final fare = dataset.tables.firstWhere(
        (t) => t.title == PortalSummaryDotReport.kTerminalFaresTableTitle,
      );
      expect(fare.rows, hasLength(41));

      final pdf = await PortalSummaryDotExport.buildPdf(
        form: form,
        dataset: dataset,
        scopeLabel: 'Misamis Occidental',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 27),
      );
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      File('${outDir.path}/MFX4_long.pdf').writeAsBytesSync(pdf);
      expect(_pdfPageCount(pdf), greaterThanOrEqualTo(2));

      final xlsx = PortalSummaryDotExport.buildXlsx(
        form: form,
        dataset: dataset,
        scopeLabel: 'Misamis Occidental',
      );
      final book = Excel.decodeBytes(xlsx);
      final sheet = book[PortalSummaryDotReport.kTerminalFaresTableTitle];
      final destCol = _findColumn(sheet, 'Destination / tourist spot')!;
      expect(
        _columnValues(sheet, destCol).where((v) => v.startsWith('Spot ')),
        hasLength(40),
      );
    });

    test('MFX 1 Excel keeps published fare strings', () {
      final form = _form(PortalSummaryDotReport.mfx1Id);
      final dataset = PortalSummaryDotReport.applyForm(_matrixDataset(), form);
      final bytes = PortalSummaryDotExport.buildXlsx(
        form: form,
        dataset: dataset,
        scopeLabel: 'Ozamiz City',
      );
      File('${outDir.path}/MFX1.xlsx').writeAsBytesSync(bytes);
      final book = Excel.decodeBytes(bytes);
      expect(
        book.tables.keys,
        containsAll(['MFX 1', 'Transportation fare matrix']),
      );
      final sheet = book['Transportation fare matrix'];
      final fareCol = _findColumn(sheet, 'Fare');
      expect(fareCol, isNotNull);
      expect(_columnValues(sheet, fareCol!), contains('PHP 45'));
    });

    test('EVT 1 PDF reuses the DOT report layout', () async {
      final form = _form(PortalSummaryDotReport.evt1Id);
      final dataset = PortalSummaryDotReport.applyForm(_eventsDataset(), form);
      final bytes = await PortalSummaryDotExport.buildPdf(
        form: form,
        dataset: dataset,
        scopeLabel: 'Misamis Occidental',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 27),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      File('${outDir.path}/EVT1.pdf').writeAsBytesSync(bytes);
      expect(_pdfPageCount(bytes), greaterThanOrEqualTo(2));

      final varForm = kDotFormCatalog.firstWhere((f) => f.id == 'var2');
      final varBytes = await buildDotReportPdfBytes(
        form: varForm,
        preview: const DotReportPreviewTable(
          title: 'Visitor record',
          headers: ['Attraction', 'This Municipality', 'Total'],
          rows: [
            ['Fort Santiago', '12', '40'],
          ],
          summaryLine: 'VAR 2 sample',
        ),
        scopeLabel: 'Oroquieta City',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 27),
      );
      expect(String.fromCharCodes(varBytes.take(5)), '%PDF-');
      File('${outDir.path}/VAR2_reference.pdf').writeAsBytesSync(varBytes);
    });

    test('EAN 1 Excel keeps both event and announcement detail rows', () {
      final form = _form(PortalSummaryDotReport.ean1Id);
      final dataset = PortalSummaryDotReport.applyForm(_eventsDataset(), form);
      expect(
        dataset.tables.map((t) => t.title),
        containsAll([
          'Tourism event records',
          'Public announcement records',
        ]),
      );
      final preview = PortalSummaryDotReport.previewTables(
        dataset,
        form: form,
      );
      expect(
        preview.firstWhere((t) => t.title == 'Tourism event records').rows,
        hasLength(2),
      );
      expect(
        preview
            .firstWhere((t) => t.title == 'Public announcement records')
            .rows,
        hasLength(1),
      );

      final bytes = PortalSummaryDotExport.buildXlsx(
        form: form,
        dataset: dataset,
        scopeLabel: 'Misamis Occidental',
      );
      File('${outDir.path}/EAN1.xlsx').writeAsBytesSync(bytes);
      final book = Excel.decodeBytes(bytes);
      final events = book['Tourism event records'];
      final announcements = book['Public announcement records'];
      expect(
        _columnValues(events, _findColumn(events, 'Event')!),
        contains('Jimenez Church Heritage Walk'),
      );
      expect(
        _columnValues(
          announcements,
          _findColumn(announcements, 'Announcement')!,
        ),
        contains('Port schedule advisory for the long weekend'),
      );
    });

    test('preview, Excel, and PDF keep the same rows for every template',
        () async {
      final cases = <(DotFormCatalogEntry, ReportDataset)>[
        for (final form in PortalSummaryDotReport.eventsForms)
          (form, PortalSummaryDotReport.applyForm(_eventsDataset(), form)),
        for (final form in PortalSummaryDotReport.matrixForms)
          (form, PortalSummaryDotReport.applyForm(_matrixDataset(), form)),
      ];
      final report = StringBuffer()
        ..writeln(
          '| Template | Table | Preview | Excel | PDF pages | Result |',
        )
        ..writeln('|---|---|---:|---:|---:|---|');

      for (final (form, dataset) in cases) {
        final preview = PortalSummaryDotReport.previewTables(
          dataset,
          form: form,
          matrixFares: dataset.kind == ReportKind.matrixFares,
        );
        expect(
          preview.map((t) => t.title).toList(),
          dataset.tables.map((t) => t.title).toList(),
          reason: form.code,
        );
        for (var i = 0; i < preview.length; i++) {
          expect(
            preview[i].rows,
            dataset.tables[i].rows,
            reason: '${form.code} ${preview[i].title}',
          );
        }

        final xlsx = PortalSummaryDotExport.buildXlsx(
          form: form,
          dataset: dataset,
          scopeLabel: 'Misamis Occidental',
        );
        File('${outDir.path}/${form.code.replaceAll(' ', '')}.xlsx')
            .writeAsBytesSync(xlsx);
        final book = Excel.decodeBytes(xlsx);
        expect(book.tables.keys, contains(form.code), reason: form.code);

        final pdf = await PortalSummaryDotExport.buildPdf(
          form: form,
          dataset: dataset,
          scopeLabel: 'Misamis Occidental',
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 27),
        );
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-', reason: form.code);
        File('${outDir.path}/${form.code.replaceAll(' ', '')}.pdf')
            .writeAsBytesSync(pdf);
        final pdfPages = _pdfPageCount(pdf);
        expect(
          pdfPages,
          greaterThanOrEqualTo(dataset.tables.length),
          reason: '${form.code} PDF must keep every section on its own page',
        );

        for (final table in dataset.tables) {
          expect(
            book.tables.keys,
            contains(table.title),
            reason: '${form.code} missing sheet ${table.title}',
          );
          final sheet = book[table.title];
          final excelRows = _excelRecordCount(sheet, table);
          expect(
            excelRows,
            table.rows.length,
            reason: '${form.code} ${table.title}',
          );
          if (table.rows.isNotEmpty) {
            expect(
              _columnValues(sheet, 0),
              contains(table.rows.first.first),
              reason: '${form.code} ${table.title} first record',
            );
          }
          report.writeln(
            '| ${form.code} | ${table.title} | ${preview.firstWhere((t) => t.title == table.title).rows.length} | $excelRows | $pdfPages | Pass |',
          );
        }
      }
      File('${outDir.path}/VERIFICATION.md').writeAsStringSync(report.toString());
    });

    test('every Events / Matrix template encodes Excel and PDF', () async {
      final cases = <(DotFormCatalogEntry, ReportDataset)>[
        for (final form in PortalSummaryDotReport.eventsForms)
          (form, PortalSummaryDotReport.applyForm(_eventsDataset(), form)),
        for (final form in PortalSummaryDotReport.matrixForms)
          (form, PortalSummaryDotReport.applyForm(_matrixDataset(), form)),
      ];
      for (final (form, dataset) in cases) {
        final xlsx = PortalSummaryDotExport.buildXlsx(
          form: form,
          dataset: dataset,
          scopeLabel: 'Misamis Occidental',
        );
        expect(xlsx.take(2).toList(), [0x50, 0x4B], reason: form.code);
        File('${outDir.path}/${form.code.replaceAll(' ', '')}.xlsx')
            .writeAsBytesSync(xlsx);

        final pdf = await PortalSummaryDotExport.buildPdf(
          form: form,
          dataset: dataset,
          scopeLabel: 'Misamis Occidental',
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 27),
        );
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-', reason: form.code);
        File('${outDir.path}/${form.code.replaceAll(' ', '')}.pdf')
            .writeAsBytesSync(pdf);

        if (form.id == PortalSummaryDotReport.mfx4Id ||
            form.id == PortalSummaryDotReport.mfx5Id) {
          final book = Excel.decodeBytes(xlsx);
          expect(
            book.tables.keys,
            contains(PortalSummaryDotReport.kTerminalFaresTableTitle),
            reason: form.code,
          );
          final sheet = book[PortalSummaryDotReport.kTerminalFaresTableTitle];
          expect(
            _columnValues(
              sheet,
              _findColumn(sheet, 'Destination / tourist spot')!,
            ),
            contains('Pipe Organ Church, Jimenez'),
            reason: form.code,
          );
        }
      }
    });
  });
}

DotFormCatalogEntry _form(String id) {
  return [
    ...PortalSummaryDotReport.eventsForms,
    ...PortalSummaryDotReport.matrixForms,
  ].firstWhere((f) => f.id == id);
}

ReportDataset _nineEventsDataset() {
  const rows = <List<String>>[
    [
      'Misamis Occidental Charter Day Celebration',
      'Festival',
      'Oroquieta City',
      'Provincial Capitol Grounds',
      'Oct 8, 2026, 8:00 AM',
      'Completed',
      '50',
    ],
    [
      'Jimenez Church Heritage Walk',
      'Tour',
      'Jimenez',
      'St. John the Baptist Church',
      'Oct 12, 2026, 3:00 PM',
      'Upcoming',
      '40',
    ],
    [
      'Perangat Festival',
      'Community',
      'Oroquieta City',
      'City Plaza',
      'Oct 16, 2026, 6:00 PM',
      'Completed',
      '25',
    ],
    [
      'Ozamiz City Fiesta',
      'Festival',
      'Ozamiz City',
      'Immaculate Conception Cathedral',
      'Oct 3, 2026, 9:00 AM',
      'Completed',
      '20',
    ],
    [
      'Tangub Christmas Symbols Festival',
      'Festival',
      'Tangub City',
      'Boulevard Area',
      'Oct 20, 2026, 7:00 PM',
      'Upcoming',
      '15',
    ],
    [
      'Sapang Dalaga River Tour',
      'Tour',
      'Sapang Dalaga',
      'Municipal Wharf',
      'Oct 18, 2026, 8:00 AM',
      'Upcoming',
      '12',
    ],
    [
      'Plaridel Coastal Fair',
      'Community',
      'Plaridel',
      'Municipal Gymnasium',
      'Oct 22, 2026, 4:00 PM',
      'Upcoming',
      '10',
    ],
    [
      'Calamba Highland Trek',
      'Tour',
      'Calamba',
      'Barangay Siloy',
      'Oct 25, 2026, 5:30 AM',
      'Upcoming',
      '8',
    ],
    [
      'Bonifacio Marine Harvest Festival',
      'Festival',
      'Bonifacio',
      'Municipal Grounds',
      'Oct 27, 2026, 10:00 AM',
      'Upcoming',
      '5',
    ],
  ];
  return ReportDataset(
    kind: ReportKind.eventsAnnouncements,
    generatedAt: DateTime(2026, 10, 27, 15, 30),
    filters: ReportFilters.none,
    periodLabel: 'Oct 1, 2026 – Oct 27, 2026',
    metrics: const [
      ReportMetric(
        label: 'Total events',
        value: '9',
        icon: Icons.event_note_outlined,
        caption: '185 check-ins on event days',
      ),
    ],
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
        rows: rows,
      ),
    ],
  );
}

ReportDataset _eventsDataset() {
  return ReportDataset(
    kind: ReportKind.eventsAnnouncements,
    generatedAt: DateTime(2026, 10, 27, 15, 30),
    filters: ReportFilters.none,
    periodLabel: 'Oct 1, 2026 – Oct 27, 2026',
    metrics: const [
      ReportMetric(
        label: 'Total events',
        value: '2',
        icon: Icons.event_note_outlined,
        caption: '1 public announcement',
      ),
    ],
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
            'Misamis Occidental Charter Day Celebration at the Provincial Capitol Grounds',
            'Festival',
            'Oroquieta City',
            'Provincial Capitol Grounds',
            'Oct 8, 2026, 8:00 AM',
            'Upcoming',
            '12',
          ],
          [
            'Jimenez Church Heritage Walk',
            'Tour',
            'Jimenez',
            'St. John the Baptist Church',
            'Oct 12, 2026, 3:00 PM',
            'Upcoming',
            '4',
          ],
        ],
      ),
      ReportTable(
        title: 'Public announcements',
        columns: ['Announcement', 'Published', 'Details'],
        rows: [
          [
            'Port schedule advisory for the long weekend',
            'Oct 5, 2026, 9:00 AM',
            'Trips may delay due to weather.',
          ],
        ],
      ),
    ],
  );
}

ReportDataset _matrixDataset({List<List<String>> extraTerminalRows = const []}) {
  return ReportDataset(
    kind: ReportKind.matrixFares,
    generatedAt: DateTime(2026, 10, 27, 15, 30),
    filters: ReportFilters.none,
    periodLabel: 'All published fares',
    metrics: const [
      ReportMetric(
        label: 'Average fare',
        value: 'PHP 45.00',
        icon: Icons.grid_on_outlined,
        caption: '2 routes',
      ),
    ],
    charts: const [],
    tables: [
      ReportTable(
        title: 'Fare matrix',
        columns: [
          'Municipality',
          'Starting point',
          'Destination / tourist spot',
          'Transportation type',
          'Fare',
          'Distance',
          'Estimated travel time',
        ],
        rows: [
          [
            'Ozamiz City',
            'Integrated Terminal',
            'Cotta Fort',
            'Multicab',
            'PHP 45',
            '4.2 km',
            '15 min',
          ],
          [
            'Ozamiz City',
            'Boulevard',
            'Pipe Organ Church, Jimenez',
            'Van',
            'PHP 120',
            '32.0 km',
            '50 min',
          ],
        ],
      ),
      ReportTable(
        title: 'Terminal to terminal fares',
        columns: [
          'Municipality',
          'Starting point',
          'Destination / tourist spot',
          'Transportation type',
          'Fare',
          'Distance',
          'Estimated travel time',
        ],
        rows: [
          [
            'Ozamiz City',
            'Boulevard',
            'Pipe Organ Church, Jimenez',
            'Van',
            'PHP 120',
            '32.0 km',
            '50 min',
          ],
          ...extraTerminalRows,
        ],
      ),
      ReportTable(
        title: 'Fare by municipality',
        columns: [
          'Municipality',
          'Routes',
          'Average fare',
          'Lowest',
          'Highest',
        ],
        numericColumns: {1},
        rows: [
          ['Ozamiz City', '2', 'PHP 82.50', 'PHP 45', 'PHP 120'],
        ],
      ),
      ReportTable(
        title: 'Fare by transportation type',
        columns: [
          'Transportation type',
          'Routes',
          'Average fare',
          'Lowest',
          'Highest',
        ],
        numericColumns: {1},
        rows: [
          ['Multicab', '1', 'PHP 45.00', 'PHP 45', 'PHP 45'],
          ['Van', '1', 'PHP 120.00', 'PHP 120', 'PHP 120'],
        ],
      ),
    ],
  );
}

String _cellText(Sheet sheet, int row, int col) {
  final value = sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
      .value;
  return value?.toString() ?? '';
}

int? _findRow(Sheet sheet, String header) {
  for (var r = 0; r < sheet.maxRows; r++) {
    if (_cellText(sheet, r, 0) == header) return r;
  }
  return null;
}

int? _findColumn(Sheet sheet, String header) {
  for (var r = 0; r < sheet.maxRows; r++) {
    for (var c = 0; c < sheet.maxColumns; c++) {
      if (_cellText(sheet, r, c) == header) return c;
    }
  }
  return null;
}

List<String> _columnValues(Sheet sheet, int col) {
  return [
    for (var r = 0; r < sheet.maxRows; r++) _cellText(sheet, r, col),
  ];
}

int _excelRecordCount(Sheet sheet, ReportTable table) {
  if (table.rows.isEmpty) {
    return _columnValues(sheet, 0).any((v) => v.startsWith('No records'))
        ? 0
        : 0;
  }
  var headerRow = -1;
  for (var r = 0; r < sheet.maxRows; r++) {
    var match = true;
    for (var c = 0; c < table.columns.length; c++) {
      if (_cellText(sheet, r, c) != table.columns[c]) {
        match = false;
        break;
      }
    }
    if (match) {
      headerRow = r;
      break;
    }
  }
  if (headerRow < 0) return -1;
  var count = 0;
  for (var r = headerRow + 1; r < sheet.maxRows; r++) {
    final first = _cellText(sheet, r, 0);
    if (first.isEmpty) continue;
    if (first == 'Total') break;
    if (first.startsWith('No records')) break;
    count++;
  }
  return count;
}

int _pdfPageCount(List<int> bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'/Type\s*/Page(?!s)').allMatches(text).length;
}
