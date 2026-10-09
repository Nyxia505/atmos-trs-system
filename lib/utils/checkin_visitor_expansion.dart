import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';
import 'package:atmos_trs_system/utils/checkin_visitor_count.dart';

/// One person behind a QR check-in, for DOT form counting.
///
/// A check-in expands to: the scanning tourist (or every "Laag with Friends"
/// group member, each with their own profile) plus companions without the app.
/// Companions carry the counts entered at scan time (Male/Female,
/// Filipino/Foreign); their residence is a proxy of the party lead.
class CheckInVisitorUnit {
  const CheckInVisitorUnit({
    required this.profile,
    this.uid,
    this.isProxy = false,
    this.residenceUnknown = false,
  });

  /// Tourist-profile-shaped map (`sex`, `country`, `nationality`, `province`,
  /// `city`, `isLocal`, `localOrForeign`). Empty when nothing is known.
  final Map<String, dynamic> profile;

  /// Account uid for real people; null for companions without the app.
  final String? uid;

  /// Residence copied from the party lead (companion without a profile).
  final bool isProxy;

  /// Filipino / foreign is known but city, province and country are not.
  final bool residenceUnknown;

  String get sex => profile['sex']?.toString().trim() ?? '';

  bool get hasProfile => profile.isNotEmpty;
}

/// Gap note shown on DOT previews that count companions.
const String kCompanionProxyGapNote =
    'Companions without the app use the sex and Filipino/Foreign counts entered '
    'at scan; their residence uses the party lead\'s address (proxy).';

/// Same rule as the DOT previews: Philippine residents are domestic.
bool isDomesticVisitorProfile(Map<String, dynamic> p) {
  final localOrForeign = p['localOrForeign']?.toString().trim() ?? '';
  if (localOrForeign.toLowerCase() == 'foreign') return false;
  if (p['isLocal'] == true) return true;
  final country = (p['country']?.toString() ?? '').trim().toLowerCase();
  final nationality = (p['nationality']?.toString() ?? '').trim().toLowerCase();
  if (country.contains('philippine') || country == 'ph' || country == 'phl') {
    return true;
  }
  if (nationality.contains('filipino') || nationality.contains('philippine')) {
    return true;
  }
  return localOrForeign.toLowerCase() == 'local';
}

/// True when [p] says whether the person is Filipino or foreign.
bool visitorHasResidencyInfo(Map<String, dynamic> p) => _hasResidencyInfo(p);

bool _hasResidencyInfo(Map<String, dynamic> p) {
  for (final k in ['localOrForeign', 'country', 'nationality']) {
    if ((p[k]?.toString().trim() ?? '').isNotEmpty) return true;
  }
  return p['isLocal'] is bool;
}

String _sexKey(String? sex) {
  final s = (sex ?? '').trim().toLowerCase();
  if (s.startsWith('f')) return 'f';
  if (s.startsWith('m')) return 'm';
  return '';
}

int _int(Object? v) {
  if (v is int) return v < 0 ? 0 : v;
  if (v is num) return v < 0 ? 0 : v.round();
  if (v is String) {
    final n = int.tryParse(v.trim());
    return n == null || n < 0 ? 0 : n;
  }
  return 0;
}

String? checkInScannerUid(Map<String, dynamic> c) {
  for (final key in ['userId', 'user_id', 'tourist_id', 'touristId']) {
    final id = c[key]?.toString().trim() ?? '';
    if (id.isNotEmpty) return id;
  }
  return null;
}

/// Scanner profile: joined `touristProfile`, else the snapshot saved on the doc.
Map<String, dynamic>? checkInScannerProfile(Map<String, dynamic> c) {
  if (c['touristProfile'] is Map) {
    return Map<String, dynamic>.from(c['touristProfile'] as Map);
  }
  final snap = <String, dynamic>{
    if ((c['touristSex']?.toString() ?? '').isNotEmpty) 'sex': c['touristSex'],
    if ((c['touristNationality']?.toString() ?? '').isNotEmpty)
      'nationality': c['touristNationality'],
    if ((c['touristCountry']?.toString() ?? '').isNotEmpty)
      'country': c['touristCountry'],
    if ((c['touristProvince']?.toString() ?? '').isNotEmpty)
      'province': c['touristProvince'],
    if ((c['touristCity']?.toString() ?? '').isNotEmpty)
      'city': c['touristCity'],
    if (c['touristIsLocal'] is bool) 'isLocal': c['touristIsLocal'],
    if ((c['touristLocalOrForeign']?.toString() ?? '').isNotEmpty)
      'localOrForeign': c['touristLocalOrForeign'],
  };
  return snap.isEmpty ? null : snap;
}

/// Group member snapshots saved on a group check-in (`groupMembers`).
List<Map<String, dynamic>> checkInGroupMembers(Map<String, dynamic> c) {
  final raw = c['groupMembers'];
  if (raw is! List) return const [];
  return [
    for (final m in raw)
      if (m is Map) Map<String, dynamic>.from(m),
  ];
}

bool isGroupCheckIn(Map<String, dynamic> c) =>
    checkInGroupMembers(c).isNotEmpty;

Map<String, dynamic> _residenceOf(Map<String, dynamic> p) => {
      for (final k in [
        'country',
        'nationality',
        'province',
        'city',
        'isLocal',
        'localOrForeign',
      ])
        if (p[k] != null) k: p[k],
    };

/// Expands one check-in into one unit per person (see [CheckInVisitorUnit]).
List<CheckInVisitorUnit> expandCheckInVisitors(
  Map<String, dynamic> c, {
  Map<String, dynamic>? scannerProfile,
}) {
  final scanner = scannerProfile ?? checkInScannerProfile(c);
  final scannerUid = checkInScannerUid(c);
  final members = checkInGroupMembers(c);
  final units = <CheckInVisitorUnit>[];

  Map<String, dynamic>? lead;
  int companions;
  int femaleLeft;
  int maleLeft;
  int? filipinoLeft;
  int? foreignLeft;

  if (members.isNotEmpty) {
    for (final m in members) {
      final uid = m['uid']?.toString().trim() ?? '';
      final useLive = scanner != null && uid.isNotEmpty && uid == scannerUid;
      final profile = useLive ? {...m, ...scanner} : m;
      units.add(CheckInVisitorUnit(
        profile: profile,
        uid: uid.isEmpty ? null : uid,
      ));
    }
    final leaderUid = c['groupLeaderUid']?.toString() ?? scannerUid ?? '';
    lead = scanner ??
        members.firstWhere(
          (m) => m['uid']?.toString() == leaderUid,
          orElse: () => members.first,
        );
    companions = _int(c['companionCount']);
    femaleLeft = _int(c['companionFemale']);
    maleLeft = _int(c['companionMale']);
    if (c.containsKey('companionFilipino') ||
        c.containsKey('companionForeign')) {
      filipinoLeft = _int(c['companionFilipino']);
      foreignLeft = _int(c['companionForeign']);
    }
  } else {
    units.add(CheckInVisitorUnit(profile: scanner ?? const {}, uid: scannerUid));
    lead = scanner;
    companions = checkInVisitorCount(c) - 1;
    femaleLeft = _int(c['femaleCount']);
    maleLeft = _int(c['maleCount']);
    final scannerSex = _sexKey(scanner?['sex']?.toString());
    if (scannerSex == 'f' && femaleLeft > 0) femaleLeft--;
    if (scannerSex == 'm' && maleLeft > 0) maleLeft--;
    if (c.containsKey('filipinoCount') || c.containsKey('foreignCount')) {
      var fil = _int(c['filipinoCount']);
      var forn = _int(c['foreignCount']);
      if (scanner != null && _hasResidencyInfo(scanner)) {
        if (isDomesticVisitorProfile(scanner)) {
          if (fil > 0) fil--;
        } else if (forn > 0) {
          forn--;
        }
      } else if (fil + forn > companions) {
        if (fil > 0) {
          fil--;
        } else if (forn > 0) {
          forn--;
        }
      }
      filipinoLeft = fil;
      foreignLeft = forn;
    }
  }

  if (companions <= 0) return units;

  final bool? leadDomestic = (lead != null && _hasResidencyInfo(lead))
      ? isDomesticVisitorProfile(lead)
      : null;

  for (var i = 0; i < companions; i++) {
    String sex = '';
    if (femaleLeft > 0) {
      sex = 'Female';
      femaleLeft--;
    } else if (maleLeft > 0) {
      sex = 'Male';
      maleLeft--;
    }

    bool? domestic = leadDomestic;
    if (filipinoLeft != null && foreignLeft != null) {
      if (filipinoLeft > 0) {
        domestic = true;
        filipinoLeft--;
      } else if (foreignLeft > 0) {
        domestic = false;
        foreignLeft--;
      }
    }

    if (domestic == null) {
      units.add(CheckInVisitorUnit(
        profile: {if (sex.isNotEmpty) 'sex': sex},
        isProxy: true,
        residenceUnknown: true,
      ));
      continue;
    }
    if (lead != null && domestic == leadDomestic) {
      units.add(CheckInVisitorUnit(
        profile: {..._residenceOf(lead), 'sex': sex},
        isProxy: true,
      ));
      continue;
    }
    units.add(CheckInVisitorUnit(
      profile: domestic
          ? {
              'country': 'Philippines',
              'nationality': 'Filipino (residence not given)',
              'localOrForeign': 'Local',
              'isLocal': true,
              'sex': sex,
            }
          : {
              'country': 'Unspecified (foreign)',
              'nationality': 'Foreign',
              'localOrForeign': 'Foreign',
              'sex': sex,
            },
      isProxy: true,
      residenceUnknown: true,
    ));
  }
  return units;
}

String _spotKey(Map<String, dynamic> c) {
  for (final k in ['spotId', 'spot_id', 'touristSpotId', 'location_id']) {
    final v = c[k]?.toString().trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  return (c['spot_name']?.toString().trim() ?? '').toLowerCase();
}

String _dayKey(Map<String, dynamic> c) {
  final t = parseCheckInTimestampFromMap(c);
  if (t == null) return '';
  return '${t.year}-${t.month}-${t.day}';
}

/// Expands every check-in into visitor units.
///
/// A group member is counted once per spot per day: skipped when they also
/// scanned alone there that day, or already appear in another group check-in.
/// Solo check-ins are expanded unchanged.
List<({Map<String, dynamic> checkIn, CheckInVisitorUnit unit})>
    expandCheckInsToVisitors(
  Iterable<Map<String, dynamic>> checkIns, {
  Map<String, dynamic>? Function(Map<String, dynamic> checkIn)? profileFor,
}) {
  final list = checkIns.toList();
  final soloKeys = <String>{};
  for (final c in list) {
    if (isGroupCheckIn(c)) continue;
    final uid = checkInScannerUid(c);
    if (uid == null) continue;
    soloKeys.add('$uid|${_spotKey(c)}|${_dayKey(c)}');
  }

  final groupSeen = <String>{};
  final out = <({Map<String, dynamic> checkIn, CheckInVisitorUnit unit})>[];
  for (final c in list) {
    final units = expandCheckInVisitors(
      c,
      scannerProfile: profileFor?.call(c),
    );
    final group = isGroupCheckIn(c);
    for (final u in units) {
      if (group && u.uid != null) {
        final key = '${u.uid}|${_spotKey(c)}|${_dayKey(c)}';
        if (soloKeys.contains(key) || !groupSeen.add(key)) continue;
      }
      out.add((checkIn: c, unit: u));
    }
  }
  return out;
}
