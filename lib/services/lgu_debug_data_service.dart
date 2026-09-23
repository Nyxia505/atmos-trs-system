import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Result of [LguDebugDataService.seedAnalyticsData].
class LguDebugSeedResult {
  const LguDebugSeedResult({
    required this.seededTourists,
    required this.seededCheckIns,
    required this.localCount,
    required this.foreignCount,
    this.raw = const {},
  });

  final int seededTourists;
  final int seededCheckIns;
  final int localCount;
  final int foreignCount;
  final Map<String, dynamic> raw;

  String get summaryMessage {
    return 'Seeded $localCount local registered tourists (by address) '
        'and $foreignCount foreign visitor profiles with $seededCheckIns check-ins. '
        'Registered Tourists KPI counts address-matched locals only.';
  }
}

/// Result of [LguDebugDataService.clearTouristData].
class LguDebugClearResult {
  const LguDebugClearResult({
    required this.deletedTourists,
    required this.deletedCheckIns,
    this.deletedStays = 0,
    this.deletedReviews = 0,
    this.municipalityId,
    this.raw = const {},
  });

  final int deletedTourists;
  final int deletedCheckIns;
  final int deletedStays;
  final int deletedReviews;
  final String? municipalityId;
  final Map<String, dynamic> raw;

  String get summaryMessage {
    final scope = (municipalityId != null && municipalityId!.isNotEmpty)
        ? 'for $municipalityId'
        : 'across the database';
    return 'Cleared $deletedTourists tourists, $deletedCheckIns check-ins, '
        '$deletedStays establishment stays, and $deletedReviews reviews $scope.';
  }
}

/// Live snapshot for the Debug data hub charts.
class LguDebugDataSnapshot {
  const LguDebugDataSnapshot({
    required this.totalTourists,
    required this.touristsByMunicipality,
    required this.totalCheckIns,
    required this.checkInsBySpot,
    required this.checkInsByMunicipality,
    required this.totalStays,
    required this.staysByStatus,
    required this.totalReviews,
  });

  final int totalTourists;
  final Map<String, int> touristsByMunicipality;
  final int totalCheckIns;
  final Map<String, int> checkInsBySpot;
  final Map<String, int> checkInsByMunicipality;
  final int totalStays;
  final Map<String, int> staysByStatus;
  final int totalReviews;
}

/// LGU Settings debug helpers: seed / clear tourist analytics data.
///
/// Prefers Cloud Functions; falls back to direct Firestore writes when Functions
/// are unavailable (e.g. Spark plan). Staff create rules must allow LGU writes.
class LguDebugDataService {
  LguDebugDataService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 120);

  static const String clearConfirmPhrase = 'CLEAR ALL TOURISTS';

  static const _firstNames = [
    'Ana', 'Ben', 'Carla', 'David', 'Erika', 'Francis', 'Grace',
    'Hector', 'Ivy', 'John', 'Karen', 'Leo', 'Mara', 'Nico', 'Olive',
    'Paolo', 'Queenie', 'Ramon', 'Sarah', 'Troy',
  ];
  static const _lastNames = [
    'Santos', 'Reyes', 'Cruz', 'Lopez', 'Garcia', 'Mendoza',
    'Ramos', 'Aquino', 'Dela Cruz', 'Torres',
  ];
  static const _foreignNationalities = [
    ('American', 'United States', 'California', 'San Francisco'),
    ('Japanese', 'Japan', '', 'Tokyo'),
    ('Korean', 'South Korea', '', 'Seoul'),
    ('Australian', 'Australia', 'NSW', 'Sydney'),
    ('Chinese', 'China', '', 'Beijing'),
  ];

  /// Seeds local registered tourists (home address = LGU) + optional foreign
  /// visitor profiles with check-ins. Foreigners are not attributed to the LGU
  /// registry (no registrationMunicipalityId / foreign city address).
  static Future<LguDebugSeedResult> seedAnalyticsData({
    required String municipalityId,
    bool seedAllMunicipalities = false,
    int? touristCount,
    int? localCount,
    int? foreignCount,
    List<String>? spotIds,
    int checkInsPerTourist = 2,
  }) async {
    final auth = FirebaseAuth.instance.currentUser;
    if (auth == null) {
      throw StateError('Sign in as LGU tourism staff, then try again.');
    }

    var local = localCount ?? 0;
    var foreign = foreignCount ?? 0;
    var total = touristCount ?? 0;
    if (local + foreign > 0) {
      total = local + foreign;
    } else if (total > 0) {
      local = (total * 0.7).round();
      foreign = total - local;
    } else {
      total = 20;
      local = 14;
      foreign = 6;
    }
    if (total > 200) {
      throw StateError('Max 200 tourists per municipality.');
    }
    final perTourist =
        (checkInsPerTourist < 1 ? 1 : checkInsPerTourist).clamp(1, 7);

    final payload = <String, dynamic>{
      'municipalityId': municipalityId.trim().toLowerCase(),
      'seedAllMunicipalities': seedAllMunicipalities,
      'checkInsPerTourist': perTourist,
      'localCount': local,
      'foreignCount': foreign,
    };
    if (spotIds != null && spotIds.isNotEmpty) {
      payload['spotIds'] = spotIds;
    }

    try {
      final callable = _functions.httpsCallable(
        'seedLguAnalyticsData',
        options: HttpsCallableOptions(timeout: _timeout),
      );
      final response = await callable.call<Map<String, dynamic>>(payload);
      final data = Map<String, dynamic>.from(response.data as Map);
      return LguDebugSeedResult(
        seededTourists: _asInt(data['seededTourists']),
        seededCheckIns: _asInt(data['seededCheckins']),
        localCount: _asInt(data['localCount']),
        foreignCount: _asInt(data['foreignCount']),
        raw: data,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[LguDebugData] seed CF: ${e.code} ${e.message}');
      if (_isFunctionsUnavailable(e)) {
        return _seedOnClient(
          municipalityId: normalizeMunicipalityId(municipalityId),
          seedAllMunicipalities: seedAllMunicipalities,
          localCount: local,
          foreignCount: foreign,
          spotIds: spotIds ?? const [],
          checkInsPerTourist: perTourist,
        );
      }
      throw StateError(userFacingError(e));
    }
  }

  /// Clears tourist profiles + check-ins. Pass [municipalityId] to scope to one LGU;
  /// omit / empty to wipe the whole tourist database.
  static Future<LguDebugClearResult> clearTouristData({
    String? municipalityId,
    required String confirmPhrase,
  }) async {
    final auth = FirebaseAuth.instance.currentUser;
    if (auth == null) {
      throw StateError('Sign in as LGU tourism staff, then try again.');
    }
    if (confirmPhrase.trim().toUpperCase() != clearConfirmPhrase) {
      throw StateError('Type $clearConfirmPhrase to confirm.');
    }

    final payload = <String, dynamic>{
      'confirmPhrase': clearConfirmPhrase,
    };
    final mun = municipalityId?.trim().toLowerCase() ?? '';
    if (mun.isNotEmpty) {
      payload['municipalityId'] = mun;
    }

    try {
      final callable = _functions.httpsCallable(
        'clearAllTouristData',
        options: HttpsCallableOptions(timeout: _timeout),
      );
      final response = await callable.call<Map<String, dynamic>>(payload);
      final data = Map<String, dynamic>.from(response.data as Map);
      final deleted = Map<String, dynamic>.from(
        (data['deleted'] as Map?) ?? const {},
      );
      final tourists = _asInt(deleted['tourists']);
      final checkIns = _asInt(deleted['qr_checkins']) +
          _asInt(deleted['checkins']) +
          _asInt(deleted['check_ins']);
      final stays = _asInt(deleted['establishment_stay_requests']);
      final reviews = _asInt(deleted['establishment_stay_reviews']);
      return LguDebugClearResult(
        deletedTourists: tourists,
        deletedCheckIns: checkIns,
        deletedStays: stays,
        deletedReviews: reviews,
        municipalityId: data['municipalityId']?.toString(),
        raw: data,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[LguDebugData] clear CF: ${e.code} ${e.message}');
      if (_isFunctionsUnavailable(e)) {
        return _clearTouristDataOnClient(municipalityId: mun);
      }
      throw StateError(userFacingError(e));
    }
  }

  static Future<LguDebugSeedResult> _seedOnClient({
    required String municipalityId,
    required bool seedAllMunicipalities,
    required int localCount,
    required int foreignCount,
    required List<String> spotIds,
    required int checkInsPerTourist,
  }) async {
    final munIds = seedAllMunicipalities
        ? getMisamisOccidentalMunicipalities()
            .map((m) => m.id)
            .toList(growable: false)
        : [
            municipalityId.isEmpty ? 'oroquieta' : municipalityId,
          ];

    var seededTourists = 0;
    var seededCheckIns = 0;
    final touristTotal = localCount + foreignCount;
    final now = DateTime.now();
    // Spread visits across the last 7 local days so "Visitors · 7 days" matches seed counts.
    final recentDays = _lastNCalendarDays(now, 7);

    WriteBatch? batch;
    var batchOps = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (batch == null) return;
      if (!force && batchOps < 400) return;
      await batch!.commit();
      batch = null;
      batchOps = 0;
    }

    void enqueueSet(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> data,
    ) {
      batch ??= _db.batch();
      batch!.set(ref, data, SetOptions(merge: true));
      batchOps += 1;
    }

    for (final munId in munIds) {
      final munName = _displayName(munId);
      var spots = await _loadSpots(munId, spotIds);
      if (spots.isEmpty) {
        final hubId = '${munId}_visitor_hub';
        await _db.collection('tourist_spots').doc(hubId).set({
          'name': '$munName Visitor Hub',
          'category': 'Resort',
          'municipalityId': munId,
          'municipality': munName,
          'status': 'Active',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        spots = [(id: hubId, name: '$munName Visitor Hub')];
      }

      for (var i = 0; i < touristTotal; i++) {
        final isLocal = i < localCount;
        final fn = _firstNames[i % _firstNames.length];
        final ln = _lastNames[i % _lastNames.length];
        final uid =
            'seed_tourist_${munId}_${(i + 1).toString().padLeft(3, '0')}';
        final email = 'seed.$munId.${i + 1}@misocc-seed.ph';
        final sex = i.isEven ? 'Female' : 'Male';
        final nationality = isLocal
            ? 'Filipino'
            : _foreignNationalities[i % _foreignNationalities.length].$1;
        final country = isLocal
            ? 'Philippines'
            : _foreignNationalities[i % _foreignNationalities.length].$2;
        final province = isLocal
            ? 'Misamis Occidental'
            : _foreignNationalities[i % _foreignNationalities.length].$3;
        final city = isLocal
            ? munName
            : _foreignNationalities[i % _foreignNationalities.length].$4;

        enqueueSet(_db.collection('tourists').doc(uid), {
          'firebaseUid': uid,
          'touristId': uid,
          'firstName': fn,
          'lastName': ln,
          'fullName': '$fn $ln',
          'email': email,
          'authEmail': email,
          'sex': sex,
          'nationality': nationality,
          'country': country,
          'province': province,
          'city': city,
          'barangay': isLocal ? 'Poblacion' : '',
          'isLocal': isLocal,
          'localOrForeign': isLocal ? 'Local' : 'Foreign',
          'partyHeadcount': 1,
          'status': 'Active',
          'isVerified': true,
          // Registry ownership = home address LGU (locals only).
          if (isLocal) 'registrationMunicipalityId': munId,
          'totalVisits': checkInsPerTourist,
          'source': 'lgu_debug_seed',
          'seedTag': 'lgu_analytics_debug_v2_address',
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        enqueueSet(_db.collection('users').doc(uid), {
          'firebaseUid': uid,
          'email': email,
          'role': 'tourist',
          'fullName': '$fn $ln',
          if (isLocal) 'municipalityId': munId,
          if (isLocal) 'municipality': munName,
          'isVerified': true,
          'source': 'lgu_debug_seed',
          'seedTag': 'lgu_analytics_debug_v2_address',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        seededTourists += 1;

        for (var j = 0; j < checkInsPerTourist; j++) {
          // Distinct calendar day per visit index (j) so dedupe keeps all N check-ins.
          final dayDate = recentDays[j % recentDays.length];
          final spot = spots[(i + j) % spots.length];
          // partySize 1 → visitors == check-ins on dashboards (clearer for debug).
          const partySize = 1;
          final femaleCount = sex == 'Female' ? 1 : 0;
          final maleCount = sex == 'Male' ? 1 : 0;
          final eventDate = DateTime(
            dayDate.year,
            dayDate.month,
            dayDate.day,
            9 + ((i + j) % 9),
            (i * 7 + j * 11) % 60,
          );
          final checkinId =
              '${uid}_${spot.id}_${dayDate.year}_'
              'm${dayDate.month}_d${dayDate.day}_v${j + 1}';
          final ts = Timestamp.fromDate(eventDate);

          enqueueSet(_db.collection('qr_checkins').doc(checkinId), {
            'userId': uid,
            'user_id': uid,
            'tourist_id': uid,
            'touristName': '$fn $ln',
            'tourist_name': '$fn $ln',
            'touristEmail': email,
            'touristNationality': nationality,
            'municipalityId': munId,
            'lguId': munId,
            'municipality': munName,
            'spotId': spot.id,
            'spot_id': spot.id,
            'touristSpotId': spot.id,
            'spot_name': spot.name,
            'spotName': spot.name,
            'location': spot.name,
            'status': 'Verified',
            'source': 'qr_scan',
            'seedTag': 'lgu_analytics_debug_v1',
            'partySize': partySize,
            'visitorCount': partySize,
            'femaleCount': femaleCount,
            'maleCount': maleCount,
            'timestamp': ts,
            'createdAt': ts,
          });

          enqueueSet(_db.collection('checkins').doc(checkinId), {
            'user_id': uid,
            'location_id': spot.id,
            'touristSpotId': spot.id,
            'lguId': munId,
            'partySize': partySize,
            'visitorCount': partySize,
            'femaleCount': femaleCount,
            'maleCount': maleCount,
            'checkin_time': ts,
            'seedTag': 'lgu_analytics_debug_v1',
          });

          seededCheckIns += 1;
          await commitIfNeeded();
        }
        await commitIfNeeded();
      }
    }
    await commitIfNeeded(force: true);

    return LguDebugSeedResult(
      seededTourists: seededTourists,
      seededCheckIns: seededCheckIns,
      localCount: localCount * munIds.length,
      foreignCount: foreignCount * munIds.length,
      raw: const {'via': 'client_batch'},
    );
  }

  static Future<List<({String id, String name})>> _loadSpots(
    String municipalityId,
    List<String> spotIdsFilter,
  ) async {
    final out = <({String id, String name})>[];
    try {
      final snap = await _db
          .collection('tourist_spots')
          .where('municipalityId', isEqualTo: municipalityId)
          .limit(100)
          .get();
      for (final doc in snap.docs) {
        if (spotIdsFilter.isNotEmpty && !spotIdsFilter.contains(doc.id)) {
          continue;
        }
        final name = doc.data()['name']?.toString().trim();
        out.add((id: doc.id, name: (name == null || name.isEmpty) ? doc.id : name));
      }
    } catch (e) {
      debugPrint('[LguDebugData] load spots: $e');
    }
    if (out.isEmpty && spotIdsFilter.isNotEmpty) {
      for (final id in spotIdsFilter) {
        out.add((id: id, name: id.replaceAll('_', ' ')));
      }
    }
    return out;
  }

  static String _displayName(String municipalityId) {
    for (final m in getMisamisOccidentalMunicipalities()) {
      if (m.id == municipalityId) return m.name;
    }
    if (municipalityId.isEmpty) return 'Misamis Occidental';
    return '${municipalityId[0].toUpperCase()}${municipalityId.substring(1)}';
  }

  /// Oldest → newest calendar days ending today (length [n], min 1).
  static List<DateTime> _lastNCalendarDays(DateTime now, int n) {
    final today = DateTime(now.year, now.month, now.day);
    final count = n < 1 ? 1 : n;
    return [
      for (var i = count - 1; i >= 0; i--)
        today.subtract(Duration(days: i)),
    ];
  }

  static Future<LguDebugClearResult> _clearTouristDataOnClient({
    required String municipalityId,
  }) async {
    var tourists = 0;
    var checkIns = 0;
    var stays = 0;
    var reviews = 0;

    if (municipalityId.isNotEmpty) {
      final touristIds = <String>{};
      final byReg = await _db
          .collection('tourists')
          .where('registrationMunicipalityId', isEqualTo: municipalityId)
          .limit(500)
          .get();
      for (final d in byReg.docs) {
        touristIds.add(d.id);
      }
      for (var i = 1; i <= 200; i++) {
        touristIds.add(
          'seed_tourist_${municipalityId}_${i.toString().padLeft(3, '0')}',
        );
      }

      tourists += await _deleteQuery(
        _db
            .collection('tourists')
            .where('registrationMunicipalityId', isEqualTo: municipalityId),
      );
      checkIns += await _deleteQuery(
        _db
            .collection('qr_checkins')
            .where('municipalityId', isEqualTo: municipalityId),
      );
      checkIns += await _deleteQuery(
        _db.collection('qr_checkins').where('lguId', isEqualTo: municipalityId),
      );
      checkIns += await _deleteQuery(
        _db.collection('checkins').where('lguId', isEqualTo: municipalityId),
      );
      stays += await _deleteQuery(
        _db
            .collection('establishment_stay_requests')
            .where('municipalityId', isEqualTo: municipalityId),
      );
      stays += await _deleteByTouristIds(
        'establishment_stay_requests',
        'touristId',
        touristIds.toList(),
      );
      reviews += await _deleteByTouristIds(
        'establishment_stay_reviews',
        'touristId',
        touristIds.toList(),
      );
      for (final uid in touristIds) {
        try {
          await _db.collection('users').doc(uid).delete();
          await _db.collection('tourists').doc(uid).delete();
          tourists += 1;
        } catch (_) {}
      }
    } else {
      tourists += await _deleteCollection('tourists');
      checkIns += await _deleteCollection('qr_checkins');
      checkIns += await _deleteCollection('checkins');
      await _deleteCollection('check_ins');
      await _deleteCollection('tourist_activity');
      stays += await _deleteCollection('establishment_stay_requests');
      reviews += await _deleteCollection('establishment_stay_reviews');
    }

    return LguDebugClearResult(
      deletedTourists: tourists,
      deletedCheckIns: checkIns,
      deletedStays: stays,
      deletedReviews: reviews,
      municipalityId: municipalityId.isEmpty ? null : municipalityId,
      raw: const {'via': 'client'},
    );
  }

  static Future<int> _deleteByTouristIds(
    String collection,
    String field,
    List<String> touristIds,
  ) async {
    var total = 0;
    final ids = touristIds.where((e) => e.trim().isNotEmpty).toList();
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      total += await _deleteQuery(
        _db.collection(collection).where(field, whereIn: chunk),
      );
    }
    return total;
  }

  /// Loads counts for the Debug hub charts (best-effort, capped reads).
  static Future<LguDebugDataSnapshot> loadSnapshot({
    String? municipalityId,
  }) async {
    final mun = municipalityId?.trim().toLowerCase() ?? '';
    final byMun = <String, int>{};
    final bySpot = <String, int>{};
    final checkInsByMun = <String, int>{};
    final staysByStatus = <String, int>{};
    var totalTourists = 0;
    var totalCheckIns = 0;
    var totalStays = 0;
    var totalReviews = 0;

    try {
      Query<Map<String, dynamic>> touristsQ = _db.collection('tourists');
      if (mun.isNotEmpty) {
        touristsQ = touristsQ.where(
          'registrationMunicipalityId',
          isEqualTo: mun,
        );
      }
      final touristsSnap = await touristsQ.limit(2000).get();
      totalTourists = touristsSnap.docs.length;
      for (final doc in touristsSnap.docs) {
        final d = doc.data();
        var key = (d['registrationMunicipalityId'] ?? '').toString().trim();
        if (key.isEmpty) {
          key = normalizeMunicipalityId(
            (d['city'] ?? d['municipality'] ?? 'unknown').toString(),
          );
        }
        if (key.isEmpty) key = 'unknown';
        byMun[key] = (byMun[key] ?? 0) + 1;
      }
    } catch (e) {
      debugPrint('[LguDebugData] tourists snapshot: $e');
    }

    try {
      Query<Map<String, dynamic>> checkQ = _db.collection('qr_checkins');
      if (mun.isNotEmpty) {
        checkQ = checkQ.where('municipalityId', isEqualTo: mun);
      }
      final checkSnap = await checkQ.limit(3000).get();
      totalCheckIns = checkSnap.docs.length;
      for (final doc in checkSnap.docs) {
        final d = doc.data();
        final spot = (d['spotName'] ?? d['attractionName'] ?? d['spotId'] ?? '')
            .toString()
            .trim();
        final spotKey = spot.isEmpty ? 'Unknown spot' : spot;
        bySpot[spotKey] = (bySpot[spotKey] ?? 0) + 1;
        var mid = (d['municipalityId'] ?? d['lguId'] ?? '').toString().trim();
        if (mid.isEmpty) mid = 'unknown';
        checkInsByMun[mid] = (checkInsByMun[mid] ?? 0) + 1;
      }
    } catch (e) {
      debugPrint('[LguDebugData] checkins snapshot: $e');
    }

    try {
      Query<Map<String, dynamic>> staysQ =
          _db.collection('establishment_stay_requests');
      if (mun.isNotEmpty) {
        staysQ = staysQ.where('municipalityId', isEqualTo: mun);
      }
      final staysSnap = await staysQ.limit(2000).get();
      totalStays = staysSnap.docs.length;
      for (final doc in staysSnap.docs) {
        final status =
            (doc.data()['status'] ?? 'unknown').toString().trim().toLowerCase();
        final key = status.isEmpty ? 'unknown' : status;
        staysByStatus[key] = (staysByStatus[key] ?? 0) + 1;
      }
    } catch (e) {
      debugPrint('[LguDebugData] stays snapshot: $e');
    }

    try {
      final reviewsSnap =
          await _db.collection('establishment_stay_reviews').limit(2000).get();
      totalReviews = reviewsSnap.docs.length;
    } catch (e) {
      debugPrint('[LguDebugData] reviews snapshot: $e');
    }

    return LguDebugDataSnapshot(
      totalTourists: totalTourists,
      touristsByMunicipality: byMun,
      totalCheckIns: totalCheckIns,
      checkInsBySpot: bySpot,
      checkInsByMunicipality: checkInsByMun,
      totalStays: totalStays,
      staysByStatus: staysByStatus,
      totalReviews: totalReviews,
    );
  }

  static Future<int> _deleteCollection(String id) async {
    return _deleteQuery(_db.collection(id));
  }

  static Future<int> _deleteQuery(Query<Map<String, dynamic>> query) async {
    var total = 0;
    while (true) {
      final snap = await query.limit(400).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      total += snap.docs.length;
      if (snap.docs.length < 400) break;
    }
    return total;
  }

  static bool _isFunctionsUnavailable(FirebaseFunctionsException e) {
    final code = e.code.toLowerCase();
    return code == 'not-found' ||
        code == 'unavailable' ||
        code == 'unimplemented' ||
        code == 'internal' ||
        (e.message ?? '').toLowerCase().contains('not found') ||
        (e.message ?? '').toLowerCase().contains('not been deployed');
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String userFacingError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'Sign in again as LGU tourism staff, then retry.';
      case 'permission-denied':
        return 'Only tourism / governor staff can run this action.';
      case 'failed-precondition':
        return e.message ?? 'This debug action is disabled on the server.';
      case 'invalid-argument':
        return e.message ?? 'Invalid seed / clear options.';
      case 'deadline-exceeded':
        return 'Timed out — try a smaller seed count or clear one LGU first.';
      case 'not-found':
        return 'Debug Cloud Functions are not deployed yet. '
            'Client fallback will be used when possible.';
      default:
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Debug action failed (${e.code}).';
    }
  }
}
