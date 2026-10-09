import 'dart:math';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/config/mice_event_types.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/models/mice_register.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/services/mice_register_service.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';

class EstablishmentDemoSeedResult {
  const EstablishmentDemoSeedResult({required this.months, required this.rows, this.events = 0});

  final int months;
  final int rows;

  /// Demo MICE events (venues with "We host events" on).
  final int events;
}

/// Seeds realistic DAE-1B register rows (tagged `seed: demo`) so the register,
/// Insights and LGU / DOT reports can be previewed. Demo rows are removable.
abstract final class EstablishmentDemoSeedService {
  static const minMonths = 1;
  static const maxMonths = 6;

  /// Rooms simulated when the AE has not set a room count yet.
  static const fallbackRooms = 8;

  static const _foreign = [
    'Japan', 'Korea (South)', 'U.S.A.', 'China', 'Australia', 'United Kingdom',
    'Germany', 'Singapore', 'Canada', 'Taiwan', 'Malaysia', 'France',
    'Netherlands', 'Uruguay', 'Cyprus',
  ];
  static const _rates = [950.0, 1200.0, 1500.0, 1800.0, 2500.0];

  static String _residence(Random r) {
    final x = r.nextDouble();
    if (x < 0.58) return DaeResidenceCatalog.phFilipino;
    if (x < 0.63) return DaeResidenceCatalog.phForeignNational;
    if (x < 0.66) return DaeResidenceCatalog.overseasFilipinos;
    if (x < 0.98) return _foreign[r.nextInt(_foreign.length)];
    return DaeResidenceCatalog.unspecified;
  }

  static String _region(Random r) => r.nextDouble() < 0.65
      ? 'Region X - Northern Mindanao'
      : DaeResidenceCatalog.philippineRegions[r.nextInt(DaeResidenceCatalog.philippineRegions.length)];

  /// Pure generator (no Firestore) — months ending with the current one,
  /// current month only up to today.
  static List<AeRegisterRow> generate({
    required AeRegisterSchema schema,
    required int totalRooms,
    int months = 3,
    DateTime? now,
    int seed = 42,
  }) {
    final r = Random(seed);
    final today = now ?? DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    final start = DateTime(today.year, today.month - (months.clamp(minMonths, maxMonths) - 1), 1);
    final rows = <AeRegisterRow>[];

    if (schema.tracksRooms) {
      final rooms = (totalRooms > 0 ? totalRooms : fallbackRooms).clamp(1, 40);
      for (var room = 1; room <= rooms; room++) {
        var day = start;
        while (!day.isAfter(end)) {
          final weekend = day.weekday >= 5;
          final p = weekend ? 0.42 : 0.2;
          if (r.nextDouble() < p) {
            final nights = 1 + r.nextInt(r.nextDouble() < 0.7 ? 2 : 5);
            final guests = 1 + r.nextInt(r.nextDouble() < 0.6 ? 2 : 4);
            final female = r.nextInt(guests + 1);
            final residence = _residence(r);
            final stay = AeRegisterCalculator.expandStay(
              checkIn: day,
              nights: nights,
              roomNo: '$room',
              residence: residence,
              phRegion: DaeResidenceCatalog.bucketFor(residence) == DaeResidenceBucket.philippineResident
                  ? _region(r)
                  : '',
              guests: guests,
              female: female,
              male: guests - female,
              rate: _rates[r.nextInt(_rates.length)],
            );
            for (final s in stay) {
              if (!s.date.isAfter(end)) rows.add(s);
            }
            day = DateTime(day.year, day.month, day.day + nights);
          } else {
            day = DateTime(day.year, day.month, day.day + 1);
          }
        }
      }
    } else {
      var day = start;
      while (!day.isAfter(end)) {
        final parties = (day.weekday >= 5 ? 6 : 2) + r.nextInt(6);
        for (var i = 0; i < parties; i++) {
          final guests = 1 + r.nextInt(5);
          final female = r.nextInt(guests + 1);
          final residence = _residence(r);
          rows.add(AeRegisterRow(
            id: '',
            date: day,
            residence: residence,
            phRegion: DaeResidenceCatalog.bucketFor(residence) == DaeResidenceBucket.philippineResident
                ? _region(r)
                : '',
            guests: guests,
            female: female,
            male: guests - female,
            checkedInDay: true,
            rate: (150 + r.nextInt(20) * 50).toDouble(),
          ));
        }
        day = DateTime(day.year, day.month, day.day + 1);
      }
    }
    return rows;
  }

  static const _miceSamples = [
    ('Provincial Planning Workshop', 'Training / Workshop', MiceCategory.meeting, 'DILG Misamis Occidental'),
    ('Sales Kick-off Meeting', 'Business meeting', MiceCategory.meeting, 'Mindanao Distributors Inc.'),
    ('Top Performers Recognition Night', 'Awards night', MiceCategory.incentive, 'Northern Agri Corp.'),
    ('Regional Nurses Convention', 'Convention', MiceCategory.convention, 'PNA Region X Chapter'),
    ('Local Products Trade Fair', 'Trade fair', MiceCategory.exhibition, 'DTI Misamis Occidental'),
    ('Santos–Reyes Wedding Reception', 'Wedding reception', MiceCategory.social, 'Santos Family'),
    ('Debut Celebration', 'Debut', MiceCategory.social, 'Dela Cruz Family'),
    ('Class Reunion 2006', 'Reunion', MiceCategory.social, 'Batch 2006 Alumni'),
    ('Barangay Health Workers Orientation', 'Government event', MiceCategory.government, 'Provincial Health Office'),
    ('Inter-school Chess Tournament', 'Sports tournament', MiceCategory.sports, 'DepEd Division Office'),
  ];
  static const _miceCountries = ['Japan', 'Korea (South)', 'U.S.A.', 'Australia', 'Singapore'];

  /// Pure generator for demo CUS events: 2–5 per month ending this month
  /// (current month only up to today).
  static List<MiceEvent> generateMiceEvents({int months = 3, DateTime? now, int seed = 7}) {
    final r = Random(seed);
    final today = now ?? DateTime.now();
    final span = months.clamp(minMonths, maxMonths);
    final out = <MiceEvent>[];
    for (var k = span - 1; k >= 0; k--) {
      final first = DateTime(today.year, today.month - k, 1);
      final lastDay = k == 0 ? today.day : DateTime(first.year, first.month + 1, 0).day;
      final count = 2 + r.nextInt(4);
      for (var i = 0; i < count; i++) {
        final s = _miceSamples[r.nextInt(_miceSamples.length)];
        final day = 1 + r.nextInt(lastDay);
        final multi = s.$3 == MiceCategory.convention || s.$3 == MiceCategory.exhibition
            ? r.nextBool()
            : r.nextDouble() < 0.1;
        final start = DateTime(first.year, first.month, day);
        final days = multi ? 2 + r.nextInt(2) : 1;
        final end = DateTime(start.year, start.month, start.day + days - 1);
        if (k == 0 && end.isAfter(today)) continue;
        final local = 20 + r.nextInt(s.$3 == MiceCategory.convention ? 280 : 130);
        final foreign = r.nextDouble() < 0.25 ? 1 + r.nextInt(12) : 0;
        final total = local + foreign;
        final male = (total * (0.35 + r.nextDouble() * 0.3)).round();
        final exhibit = s.$3 == MiceCategory.exhibition || (s.$3 == MiceCategory.convention && r.nextBool());
        out.add(MiceEvent(
          id: '',
          dateStart: start,
          dateEnd: days > 1 ? end : null,
          eventName: s.$1,
          eventType: s.$2,
          category: s.$3,
          hours: (days * (s.$3 == MiceCategory.social ? 5 : 8)).toDouble(),
          foreign: foreign,
          local: local,
          male: male,
          female: total - male,
          hasExhibit: exhibit,
          exhibitors: exhibit ? 5 + r.nextInt(30) : 0,
          exhibitVisitors: exhibit ? 100 + r.nextInt(900) : 0,
          organizerName: s.$4,
          organizerAddress: 'Oroquieta City, Misamis Occidental',
          contactPerson: 'Event Coordinator',
          contactNo: '0917${(1000000 + r.nextInt(8999999))}',
          foreignCountries: foreign == 0 ? const {} : {_miceCountries[r.nextInt(_miceCountries.length)]: foreign},
          isDemo: true,
        ));
      }
    }
    return out;
  }

  /// Replaces this AE's demo rows with [months] months of generated data
  /// (plus demo MICE events when [hostsMice]).
  static Future<EstablishmentDemoSeedResult> seed({
    required AeRegisterProfile profile,
    required AeRegisterSchema schema,
    int months = 3,
    bool hostsMice = false,
  }) async {
    await clear(profile.aeId);
    final effective = schema.tracksRooms && profile.totalRooms <= 0
        ? AeRegisterProfile(
            aeId: profile.aeId,
            aeName: profile.aeName,
            municipalityId: profile.municipalityId,
            municipality: profile.municipality,
            totalRooms: fallbackRooms,
            aeType: profile.aeType,
            classificationCode: profile.classificationCode,
            category: profile.category,
          )
        : profile;
    final rows = generate(
      schema: schema,
      totalRooms: effective.totalRooms,
      months: months,
      seed: DateTime.now().millisecondsSinceEpoch,
    );
    await AeRegisterService.applyChanges(profile: effective, upserts: rows, seedDemo: true);
    final events = hostsMice
        ? generateMiceEvents(months: months, seed: DateTime.now().millisecondsSinceEpoch)
        : const <MiceEvent>[];
    if (events.isNotEmpty) {
      await MiceRegisterService.applyChanges(profile: effective, upserts: events, seedDemo: true);
    }
    final monthKeys = {for (final x in rows) '${x.date.year}-${x.date.month}'};
    return EstablishmentDemoSeedResult(months: monthKeys.length, rows: rows.length, events: events.length);
  }

  /// Deletes demo-seeded register months and MICE events for this AE.
  /// Returns register months removed.
  static Future<int> clear(String aeId) async {
    final months = await AeRegisterService.deleteDemo(aeId: aeId);
    await MiceRegisterService.deleteDemo(aeId: aeId);
    return months;
  }
}
