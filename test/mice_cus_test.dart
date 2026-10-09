import 'dart:io';

import 'package:atmos_trs_system/config/mice_event_types.dart';
import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/models/mice_register.dart';
import 'package:atmos_trs_system/services/establishment_demo_seed_service.dart';
import 'package:atmos_trs_system/utils/dot_report_export_service.dart';
import 'package:atmos_trs_system/utils/dot_report_pdf_export.dart';
import 'package:atmos_trs_system/utils/dot_report_preview.dart';
import 'package:atmos_trs_system/utils/mice_register_calculator.dart';
import 'package:atmos_trs_system/utils/mice_report_query.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

MiceEvent _event(
  String id,
  DateTime start, {
  DateTime? end,
  String name = 'Event',
  double hours = 4,
  int foreign = 0,
  int local = 10,
  int? male,
  bool exhibit = false,
  int exhibitors = 0,
  int visitors = 0,
  MiceCategory category = MiceCategory.meeting,
  String type = 'Seminar',
}) {
  final total = foreign + local;
  final m = male ?? total ~/ 2;
  return MiceEvent(
    id: id,
    dateStart: start,
    dateEnd: end,
    eventName: name,
    eventType: type,
    category: category,
    hours: hours,
    foreign: foreign,
    local: local,
    male: m,
    female: total - m,
    hasExhibit: exhibit,
    exhibitors: exhibitors,
    exhibitVisitors: visitors,
    organizerName: 'Org $id',
    contactNo: '0917',
  );
}

MiceReportData _data({
  required Map<MiceMonthlyReport, List<MiceEvent>> months,
  DateTime? start,
  DateTime? end,
}) =>
    MiceReportData(
      reports: months.keys.toList(),
      eventsByReport: {for (final e in months.entries) e.key.id: e.value},
      startDate: start ?? DateTime(2026, 10, 1),
      endDate: end ?? DateTime(2026, 10, 31),
    );

MiceMonthlyReport _report(String aeId, String name, {AeReportStatus status = AeReportStatus.submitted}) =>
    MiceMonthlyReport(
      id: '${aeId}_2026_10',
      aeId: aeId,
      year: 2026,
      month: 10,
      aeName: name,
      municipality: 'Oroquieta City',
      status: status,
      totals: const MiceMonthTotals(events: 1),
    );

String? _cell(Sheet s, String a1) => s.cell(CellIndex.indexByString(a1)).value?.toString();

void main() {
  group('MiceRegisterCalculator', () {
    test('control numbers follow date order and totals add up', () {
      final events = [
        _event('b', DateTime(2026, 10, 9), local: 20, foreign: 5, hours: 2.5),
        _event('a', DateTime(2026, 10, 2), local: 10, exhibit: true, exhibitors: 4, visitors: 50),
      ];
      expect(MiceRegisterCalculator.controlNumbers(events), {'a': 1, 'b': 2});
      final t = MiceRegisterCalculator.totals(events);
      expect(t.events, 2);
      expect(t.attendees, 35);
      expect(t.foreign, 5);
      expect(t.hours, 6.5);
      expect(t.exhibitions, 1);
      expect(t.exhibitVisitors, 50);
    });

    test('validation blocks sex split mismatch and bad dates', () {
      final ok = _event('a', DateTime(2026, 10, 2));
      expect(MiceRegisterCalculator.validate(ok), isEmpty);
      final bad = ok.copyWith(male: 1, female: 1, dateEnd: DateTime(2026, 9, 1));
      final issues = MiceRegisterCalculator.validate(bad);
      expect(issues.any((i) => i.contains('Male + Female')), isTrue);
      expect(issues.any((i) => i.contains('End date')), isTrue);
    });

    test('multi-day date label', () {
      final e = _event('a', DateTime(2026, 10, 5), end: DateTime(2026, 10, 7));
      expect(MiceRegisterCalculator.dateLabel(e), '10/5–7/2026');
      expect(e.days, 3);
    });
  });

  group('Demo MICE seed', () {
    test('generated events are valid and use suggestion types', () {
      final events = EstablishmentDemoSeedService.generateMiceEvents(months: 6, now: DateTime(2026, 10, 15), seed: 3);
      expect(events, isNotEmpty);
      for (final e in events) {
        expect(MiceRegisterCalculator.validate(e), isEmpty, reason: e.eventName);
        expect(MiceEventTypes.find(e.eventType, MiceEventTypes.base), isNotNull, reason: e.eventType);
        expect(e.lastDay.isAfter(DateTime(2026, 10, 15)), isFalse);
        expect(e.isDemo, isTrue);
      }
    });
  });

  group('MiceEventTypes', () {
    test('suggestions map to categories and custom types merge', () {
      expect(MiceEventTypes.find('seminar', MiceEventTypes.base)?.category, MiceCategory.meeting);
      expect(MiceEventTypes.guessCategory('Wedding Reception'), MiceCategory.social);
      final merged = MiceEventTypes.merged([const MiceEventType('Drone Expo', MiceCategory.exhibition, custom: true)]);
      expect(MiceEventTypes.search('drone', merged).first.label, 'Drone Expo');
    });
  });

  group('CUS preview', () {
    test('single venue: no establishment column, TOTAL footer', () {
      final data = _data(months: {
        _report('h1', 'Hotel One'): [
          _event('a', DateTime(2026, 10, 2), local: 10),
          _event('b', DateTime(2026, 10, 9), local: 20, foreign: 5),
        ],
      });
      final p = buildCusMicePreview(form: DotReportType.cusMice.catalogEntry, mice: data, scopeLabel: 'Oroquieta');
      expect(p.headers.contains('Establishment'), isFalse);
      expect(p.rows.length, 2);
      expect(p.rows.first.first, '1');
      expect(p.footer![p.headers.indexOf('Total')], '35');
    });

    test('several venues add the establishment column', () {
      final data = _data(months: {
        _report('h1', 'Hotel One'): [_event('a', DateTime(2026, 10, 2))],
        _report('h2', 'Hall Two'): [_event('c', DateTime(2026, 10, 1))],
      });
      final p = buildCusMicePreview(form: DotReportType.cusMice.catalogEntry, mice: data, scopeLabel: 'Oroquieta');
      final col = p.headers.indexOf('Establishment');
      expect(col, greaterThan(0));
      expect(p.rows.first[col], 'Hall Two');
    });
  });

  group('CUS PDF', () {
    test('builds with officer / mayor signatory lines', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final data = _data(months: {_report('h1', 'Hotel One'): [_event('a', DateTime(2026, 10, 2))]});
      final form = DotReportType.cusMice.catalogEntry;
      final bytes = await buildDotReportPdfBytes(
        form: form,
        preview: buildCusMicePreview(form: form, mice: data, scopeLabel: 'Oroquieta City'),
        scopeLabel: 'Oroquieta City',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
        signatories: const [
          DotPdfSignatory(role: 'Name of Tourism Officer', name: 'Juan Dela Cruz'),
          DotPdfSignatory(role: 'Mayor'),
        ],
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });

  group('CUS Excel writer', () {
    final templateFile = File('forms_format/CUS-FORM-MICE-UTILIZATION-SURVEY-FORM.xlsx');

    test('fills SUMMARY + one BY EST per venue on the official template', () {
      final data = _data(months: {
        _report('h1', 'Hotel One'): [
          _event('a', DateTime(2026, 10, 2), name: 'Sales Kickoff', hours: 2.5, local: 30, foreign: 2),
        ],
        _report('h2', 'Hall Two'): [_event('c', DateTime(2026, 10, 1), name: 'Wedding', local: 120)],
      });
      final result = DotReportExportService().buildCusWorkbook(
        templateBytes: templateFile.readAsBytesSync(),
        templateSource: 'test',
        mice: data,
        options: const CusExportOptions(officerName: 'Juan Dela Cruz', mayorName: 'Maria Clara'),
        scopeLabel: 'Oroquieta City',
        scopeSlug: 'oroquieta',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
      );
      final x = Excel.decodeBytes(result.bytes);
      expect(x.tables.keys, containsAll(['CUS SUMMARY', 'Hotel One', 'Hall Two', 'ATMOS_DATA', 'ATMOS_GAPS']));
      expect(x.tables.keys.any((k) => k.startsWith('Sheet')), isFalse);
      expect(x.tables.containsKey('CUS BY EST'), isFalse);

      final s = x['CUS SUMMARY'];
      expect(_cell(s, 'C2'), contains('OCTOBER'));
      expect(_cell(s, 'C8'), 'Wedding');
      expect(_cell(s, 'D8'), 'Hall Two');
      expect(_cell(s, 'C9'), 'Sales Kickoff');
      expect(_cell(s, 'E9'), '2.5');
      expect(_cell(s, 'I9'), '32');
      expect(_cell(s, 'B10'), 'TOTAL');
      expect(_cell(s, 'I10'), '152');

      final h = x['Hotel One'];
      expect(_cell(h, 'A4'), contains('Hotel One'));
      expect(_cell(h, 'A10'), '1');
      expect(_cell(h, 'C10'), 'Sales Kickoff');
      expect(_cell(h, 'H10'), '32');
      expect(_cell(h, 'C33'), 'JUAN DELA CRUZ');
      expect(_cell(h, 'K33'), 'MARIA CLARA');
    });

    test('overflow beyond 20 rows inserts rows and shifts the footer', () {
      final events = [
        for (var i = 0; i < 25; i++) _event('e$i', DateTime(2026, 10, 1 + i), name: 'Event $i'),
      ];
      final data = _data(months: {_report('h1', 'Hotel One'): events});
      final result = DotReportExportService().buildCusWorkbook(
        templateBytes: templateFile.readAsBytesSync(),
        mice: data,
        options: const CusExportOptions(officerName: 'Officer'),
        scopeLabel: 'Oroquieta City',
        scopeSlug: 'oroquieta',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
      );
      final x = Excel.decodeBytes(result.bytes);
      final h = x['Hotel One'];
      expect(_cell(h, 'C34'), 'Event 24');
      expect(_cell(h, 'B35'), 'TOTAL');
      expect(_cell(h, 'C39'), 'OFFICER');
    });

    test('summary-only and venues-only layouts', () {
      final data = _data(months: {
        _report('h1', 'Hotel One'): [_event('a', DateTime(2026, 10, 2))],
        _report('h2', 'Hall Two'): [_event('c', DateTime(2026, 10, 1))],
      });
      DotReportExportResult build(CusLayout layout) => DotReportExportService().buildCusWorkbook(
            templateBytes: templateFile.readAsBytesSync(),
            mice: data,
            options: CusExportOptions(layout: layout),
            scopeLabel: 'Oroquieta City',
            scopeSlug: 'oroquieta',
            startDate: DateTime(2026, 10, 1),
            endDate: DateTime(2026, 10, 31),
          );
      final summary = Excel.decodeBytes(build(CusLayout.summaryOnly).bytes);
      expect(summary.tables.keys.where((k) => !k.startsWith('ATMOS_')), ['CUS SUMMARY']);
      expect(_cell(summary['CUS SUMMARY'], 'C8'), 'Event');
      final venues = Excel.decodeBytes(build(CusLayout.venuesOnly).bytes);
      expect(venues.tables.keys.where((k) => !k.startsWith('ATMOS_')).toSet(), {'Hotel One', 'Hall Two'});
      expect(_cell(venues['Hall Two'], 'A4'), contains('Hall Two'));
    });

    test('builds an equivalent workbook without a template', () {
      final data = _data(months: {_report('h1', 'Hotel One'): [_event('a', DateTime(2026, 10, 2))]});
      final result = DotReportExportService().buildCusWorkbook(
        templateBytes: null,
        mice: data,
        scopeLabel: 'Oroquieta City',
        scopeSlug: 'oroquieta',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
      );
      expect(result.gaps.any((g) => g.contains('template unavailable')), isTrue);
      final x = Excel.decodeBytes(result.bytes);
      expect(_cell(x['Hotel One'], 'C10'), 'Event');
    });
  });
}
