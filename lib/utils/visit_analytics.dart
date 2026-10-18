import 'package:atmos_trs_system/services/governor_firestore_service.dart';
import 'package:atmos_trs_system/utils/checkin_visitor_count.dart';
import 'package:atmos_trs_system/utils/checkin_visitor_expansion.dart';

/// Visitor analytics from QR check-ins, including origin male/female counts.
class VisitAnalyticsSnapshot {
  const VisitAnalyticsSnapshot({
    required this.dailyAverage,
    required this.peakHour,
    required this.topOrigin,
    required this.male,
    required this.female,
    required this.otherGender,
    required this.local,
    required this.foreign,
    required this.ageSeries,
    required this.categories,
    required this.municipalities,
    required this.spots,
    required this.arrivals,
  });

  final int dailyAverage;
  final String peakHour;
  final String topOrigin;
  final int male;
  final int female;
  final int otherGender;
  final int local;
  final int foreign;
  final List<({String label, int male, int female, int others})> ageSeries;
  final List<({String name, int count})> categories;
  final List<({String name, int count})> municipalities;
  final List<({String name, int count})> spots;
  final List<double> arrivals;

  static const ageLabels = [
    '0-17',
    '18-24',
    '25-34',
    '35-44',
    '45-54',
    '55+',
  ];

  factory VisitAnalyticsSnapshot.build({
    required List<Map<String, dynamic>> checkIns,
    List<Map<String, dynamic>> tourists = const [],
    String range = 'This Month',
    DateTime? now,
    DateTime? Function(Map<String, dynamic> checkIn)? parseTime,
  }) {
    final clock = now ?? DateTime.now();
    final readTime = parseTime ?? GovernorFirestoreService.parseCheckInTime;
    final profiles = _profilesByUid(tourists);

    var male = 0;
    var female = 0;
    var otherGender = 0;
    var local = 0;
    var foreign = 0;
    final ages = <String, ({int male, int female, int others})>{
      for (final label in ageLabels) label: (male: 0, female: 0, others: 0),
    };
    final origins = <String, int>{};
    final categories = <String, int>{};
    final municipalities = <String, int>{};
    final spots = <String, int>{};
    final hours = <int, int>{};
    final days = <DateTime>{};
    var visitors = 0;

    for (final raw in checkIns) {
      final checkIn = _withProfile(raw, profiles);
      final units = expandCheckInVisitors(checkIn);
      final weight = units.isEmpty ? checkInVisitorCount(checkIn) : units.length;
      visitors += weight;

      final when = readTime(checkIn);
      if (when != null) {
        days.add(DateTime(when.year, when.month, when.day));
        hours[when.hour] = (hours[when.hour] ?? 0) + weight;
      }

      final category = _categoryOf(checkIn);
      categories[category] = (categories[category] ?? 0) + weight;
      final municipality = _municipalityOf(checkIn);
      if (municipality.isNotEmpty) {
        municipalities[municipality] =
            (municipalities[municipality] ?? 0) + weight;
      }
      final spot = _spotOf(checkIn);
      if (spot.isNotEmpty) {
        spots[spot] = (spots[spot] ?? 0) + weight;
      }

      for (final unit in units) {
        final sex = _sexLabel(unit.sex);
        if (sex == 'Male') {
          male++;
        } else if (sex == 'Female') {
          female++;
        } else if (sex == 'Others') {
          otherGender++;
        }

        if (visitorHasResidencyInfo(unit.profile)) {
          if (isDomesticVisitorProfile(unit.profile)) {
            local++;
          } else {
            foreign++;
          }
        }

        final origin = _originLabel(unit);
        if (origin != null) {
          origins[origin] = (origins[origin] ?? 0) + 1;
        }

        final age = _ageYears(_profileForAge(unit, profiles), clock);
        final bucket = _ageBucket(age);
        if (bucket == null || sex == null) continue;
        final current = ages[bucket]!;
        if (sex == 'Male') {
          ages[bucket] = (
            male: current.male + 1,
            female: current.female,
            others: current.others,
          );
        } else if (sex == 'Female') {
          ages[bucket] = (
            male: current.male,
            female: current.female + 1,
            others: current.others,
          );
        } else {
          ages[bucket] = (
            male: current.male,
            female: current.female,
            others: current.others + 1,
          );
        }
      }
    }

    final span = _daySpan(days);
    return VisitAnalyticsSnapshot(
      dailyAverage: span == 0 ? 0 : (visitors / span).round(),
      peakHour: _peakHour(hours),
      topOrigin: _topKey(origins),
      male: male,
      female: female,
      otherGender: otherGender,
      local: local,
      foreign: foreign,
      ageSeries: [
        for (final label in ageLabels)
          (
            label: label,
            male: ages[label]!.male,
            female: ages[label]!.female,
            others: ages[label]!.others,
          ),
      ],
      categories: _ranked(categories, 5),
      municipalities: _ranked(municipalities, 8),
      spots: _ranked(spots, 8),
      arrivals: _arrivals(checkIns, readTime, range, clock),
    );
  }
}

Map<String, Map<String, dynamic>> _profilesByUid(
  List<Map<String, dynamic>> tourists,
) {
  final out = <String, Map<String, dynamic>>{};
  for (final tourist in tourists) {
    for (final key in ['id', 'uid', 'userId', 'user_id']) {
      final id = tourist[key]?.toString().trim() ?? '';
      if (id.isNotEmpty) out[id] = tourist;
    }
  }
  return out;
}

Map<String, dynamic> _withProfile(
  Map<String, dynamic> checkIn,
  Map<String, Map<String, dynamic>> profiles,
) {
  if (checkIn['touristProfile'] is Map) return checkIn;
  final uid = checkInScannerUid(checkIn);
  final profile = uid == null ? null : profiles[uid];
  if (profile == null) return checkIn;
  return {...checkIn, 'touristProfile': profile};
}

Map<String, dynamic>? _profileForAge(
  CheckInVisitorUnit unit,
  Map<String, Map<String, dynamic>> profiles,
) {
  final uid = unit.uid;
  if (uid != null && profiles.containsKey(uid)) return profiles[uid];
  if (!unit.isProxy && unit.profile['dateOfBirth'] != null) return unit.profile;
  return null;
}

String? _sexLabel(String raw) {
  final sex = raw.trim().toLowerCase();
  if (sex.isEmpty) return null;
  if (sex.startsWith('f')) return 'Female';
  if (sex == 'm' || sex.startsWith('male')) return 'Male';
  return 'Others';
}

String? _ageBucket(int? age) {
  if (age == null || age < 0 || age > 120) return null;
  if (age < 18) return '0-17';
  if (age <= 24) return '18-24';
  if (age <= 34) return '25-34';
  if (age <= 44) return '35-44';
  if (age <= 54) return '45-54';
  return '55+';
}

int? _ageYears(Map<String, dynamic>? profile, DateTime now) {
  if (profile == null) return null;
  final dob = profile['dateOfBirth']?.toString().trim() ?? '';
  if (dob.isEmpty) return null;
  final birth = DateTime.tryParse(dob);
  if (birth == null) return null;
  var age = now.year - birth.year;
  if (now.month < birth.month ||
      (now.month == birth.month && now.day < birth.day)) {
    age--;
  }
  return age;
}

String? _originLabel(CheckInVisitorUnit unit) {
  if (unit.residenceUnknown) return null;
  final city = unit.profile['city']?.toString().trim() ?? '';
  if (city.isNotEmpty) return city;
  if (!isDomesticVisitorProfile(unit.profile)) {
    final country = unit.profile['country']?.toString().trim() ?? '';
    if (country.isNotEmpty && !country.toLowerCase().contains('unspecified')) {
      return country;
    }
  }
  final province = unit.profile['province']?.toString().trim() ?? '';
  if (province.isNotEmpty) return province;
  return null;
}

String _categoryOf(Map<String, dynamic> checkIn) {
  final raw = checkIn['spotCategory']?.toString().trim() ??
      checkIn['category']?.toString().trim() ??
      '';
  return raw.isEmpty ? 'Other' : raw;
}

String _municipalityOf(Map<String, dynamic> checkIn) {
  final name = checkIn['municipality']?.toString().trim() ?? '';
  if (name.isNotEmpty) return name;
  return checkIn['municipalityId']?.toString().trim() ?? '';
}

String _spotOf(Map<String, dynamic> checkIn) {
  for (final key in ['spot_name', 'spotName', 'location', 'name']) {
    final value = checkIn[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

int _daySpan(Set<DateTime> days) {
  if (days.isEmpty) return 0;
  final sorted = days.toList()..sort();
  return sorted.last.difference(sorted.first).inDays + 1;
}

String _peakHour(Map<int, int> hours) {
  if (hours.isEmpty) return '—';
  final top = hours.entries.reduce((a, b) => a.value >= b.value ? a : b);
  final start = top.key;
  final end = (start + 1) % 24;
  String clock(int hour) {
    if (hour == 0) return '12';
    if (hour > 12) return '${hour - 12}';
    return '$hour';
  }

  final suffix = end < 12 || end == 0 ? 'AM' : 'PM';
  return '${clock(start)}-${clock(end)} $suffix';
}

String _topKey(Map<String, int> counts) {
  if (counts.isEmpty) return '—';
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

List<({String name, int count})> _ranked(Map<String, int> counts, int limit) {
  final rows = counts.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final row in rows.take(limit)) (name: row.key, count: row.value),
  ];
}

List<double> _arrivals(
  List<Map<String, dynamic>> checkIns,
  DateTime? Function(Map<String, dynamic>) readTime,
  String range,
  DateTime now,
) {
  if (range == 'This Year') {
    final counts = List<double>.filled(12, 0);
    for (final checkIn in checkIns) {
      final when = readTime(checkIn);
      if (when == null) continue;
      final diff = (now.year - when.year) * 12 + (now.month - when.month);
      if (diff >= 0 && diff < 12) {
        counts[11 - diff] += checkInVisitorCount(checkIn);
      }
    }
    return counts;
  }

  if (range == 'This Month') {
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final counts = List<double>.filled(daysInMonth, 0);
    for (final checkIn in checkIns) {
      final when = readTime(checkIn);
      if (when == null) continue;
      if (when.year == now.year && when.month == now.month) {
        counts[when.day - 1] += checkInVisitorCount(checkIn);
      }
    }
    return counts;
  }

  final days = range == 'This Week' ? 7 : 14;
  final counts = List<double>.filled(days, 0);
  for (final checkIn in checkIns) {
    final when = readTime(checkIn);
    if (when == null) continue;
    final day = DateTime(when.year, when.month, when.day);
    final diff = DateTime(now.year, now.month, now.day).difference(day).inDays;
    if (diff >= 0 && diff < days) {
      counts[days - 1 - diff] += checkInVisitorCount(checkIn);
    }
  }
  return counts;
}
