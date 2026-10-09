import 'dart:async';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/services/establishment_demo_seed_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Progress of [LguDebugDataService.seedAnalyticsData]: [done] of [total] LGUs
/// finished; [municipalityName] is the LGU now being seeded (empty when done).
typedef LguDebugSeedProgress = void Function(
  int done,
  int total,
  String municipalityName,
);

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
    final lguCount = (raw['municipalities'] as int?) ?? 1;
    final scope = lguCount > 1 ? ' across $lguCount LGUs' : '';
    return 'Seeded $localCount local registered tourists (by address) '
        'and $foreignCount foreign visitor profiles with $seededCheckIns check-ins$scope. '
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
    this.deletedDemoRegisters = 0,
    this.municipalityId,
    this.raw = const {},
  });

  final int deletedTourists;
  final int deletedCheckIns;
  final int deletedStays;
  final int deletedReviews;

  /// Demo-seeded hotel register months (`ae_monthly_reports`, seed: demo).
  final int deletedDemoRegisters;
  final String? municipalityId;
  final Map<String, dynamic> raw;

  String get summaryMessage {
    final scope = (municipalityId != null && municipalityId!.isNotEmpty)
        ? 'for $municipalityId'
        : 'across the database';
    final legacy = deletedStays + deletedReviews;
    return 'Cleared $deletedTourists tourists, $deletedCheckIns check-ins, '
        '$deletedDemoRegisters demo hotel register month(s)'
        '${legacy > 0 ? ', and $legacy legacy stay/review docs' : ''} $scope.';
  }

  LguDebugClearResult withDemoRegisters(int n) => LguDebugClearResult(
        deletedTourists: deletedTourists,
        deletedCheckIns: deletedCheckIns,
        deletedStays: deletedStays,
        deletedReviews: deletedReviews,
        deletedDemoRegisters: n,
        municipalityId: municipalityId,
        raw: raw,
      );
}

/// Result of [LguDebugDataService.seedHotelRegisters].
class LguDebugRegisterSeedResult {
  const LguDebugRegisterSeedResult({
    required this.establishments,
    required this.months,
    required this.rows,
    this.failed = 0,
  });

  final int establishments;
  final int months;
  final int rows;
  final int failed;

  String get summaryMessage => establishments == 0
      ? 'No active lodging establishments in scope — approve one in OPTACA first.'
      : 'Seeded $rows demo register rows ($months AE-months) for $establishments '
          'establishment(s)${failed > 0 ? ' · $failed failed' : ''}.';
}

/// Live snapshot for the Debug data hub charts.
class LguDebugDataSnapshot {
  const LguDebugDataSnapshot({
    required this.totalTourists,
    required this.touristsByMunicipality,
    required this.totalCheckIns,
    required this.checkInsBySpot,
    required this.checkInsByMunicipality,
    required this.totalRegisters,
    required this.registersByStatus,
    required this.registerGuestNights,
    required this.legacyStayDocs,
  });

  final int totalTourists;
  final Map<String, int> touristsByMunicipality;
  final int totalCheckIns;
  final Map<String, int> checkInsBySpot;
  final Map<String, int> checkInsByMunicipality;

  /// Hotel DOT register months (`ae_monthly_reports`) in scope.
  final int totalRegisters;

  /// Submitted / Draft / Demo (demo wins over status).
  final Map<String, int> registersByStatus;
  final int registerGuestNights;

  /// Retired `establishment_stay_requests` + `establishment_stay_reviews` still present.
  final int legacyStayDocs;
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
    LguDebugSeedProgress? onProgress,
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

    final primaryId = normalizeMunicipalityId(municipalityId);
    final primary = primaryId.isEmpty ? 'oroquieta' : primaryId;
    final targets = seedAllMunicipalities
        ? [
            for (final m in getMisamisOccidentalMunicipalities())
              (id: m.id, name: m.name),
          ]
        : [(id: primary, name: _displayName(primary))];

    // One LGU per call keeps each request well under the callable timeout and
    // lets the UI show which LGU is being seeded.
    var seededTourists = 0;
    var seededCheckIns = 0;
    var useCloud = true;
    final perMunicipality = <String, dynamic>{};
    for (var k = 0; k < targets.length; k++) {
      final target = targets[k];
      onProgress?.call(k, targets.length, target.name);
      // Spot chips belong to the primary LGU; other LGUs use their own spots.
      final munSpotIds = target.id == primary
          ? (spotIds ?? const <String>[])
          : const <String>[];
      LguDebugSeedResult? result;
      if (useCloud) {
        try {
          result = await _seedOneViaCloud(
            municipalityId: target.id,
            localCount: local,
            foreignCount: foreign,
            spotIds: munSpotIds,
            checkInsPerTourist: perTourist,
          );
        } on FirebaseFunctionsException catch (e) {
          debugPrint('[LguDebugData] seed CF: ${e.code} ${e.message}');
          if (!_isFunctionsUnavailable(e)) {
            throw StateError(userFacingError(e));
          }
          useCloud = false;
        }
      }
      result ??= await _seedOnClient(
        municipalityId: target.id,
        seedAllMunicipalities: false,
        localCount: local,
        foreignCount: foreign,
        spotIds: munSpotIds,
        checkInsPerTourist: perTourist,
      );
      seededTourists += result.seededTourists;
      seededCheckIns += result.seededCheckIns;
      perMunicipality[target.id] = {
        'tourists': result.seededTourists,
        'checkIns': result.seededCheckIns,
      };
    }
    onProgress?.call(targets.length, targets.length, '');

    return LguDebugSeedResult(
      seededTourists: seededTourists,
      seededCheckIns: seededCheckIns,
      localCount: local * targets.length,
      foreignCount: foreign * targets.length,
      raw: {
        'seedAllMunicipalities': seedAllMunicipalities,
        'municipalities': targets.length,
        'via': useCloud ? 'cloud_function' : 'client',
        'perMunicipality': perMunicipality,
      },
    );
  }

  static Future<LguDebugSeedResult> _seedOneViaCloud({
    required String municipalityId,
    required int localCount,
    required int foreignCount,
    required List<String> spotIds,
    required int checkInsPerTourist,
  }) async {
    final payload = <String, dynamic>{
      'municipalityId': municipalityId,
      'seedAllMunicipalities': false,
      'checkInsPerTourist': checkInsPerTourist,
      'localCount': localCount,
      'foreignCount': foreignCount,
      if (spotIds.isNotEmpty) 'spotIds': spotIds,
    };
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
      final result = LguDebugClearResult(
        deletedTourists: tourists,
        deletedCheckIns: checkIns,
        deletedStays: stays,
        deletedReviews: reviews,
        municipalityId: data['municipalityId']?.toString(),
        raw: data,
      );
      return result.withDemoRegisters(await _deleteDemoRegisters(mun));
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[LguDebugData] clear CF: ${e.code} ${e.message}');
      if (_isFunctionsUnavailable(e)) {
        final result = await _clearTouristDataOnClient(municipalityId: mun);
        return result.withDemoRegisters(await _deleteDemoRegisters(mun));
      }
      throw StateError(userFacingError(e));
    }
  }

  static Future<int> _deleteDemoRegisters(String municipalityId) async {
    try {
      return await AeRegisterService.deleteDemo(
        municipalityId: municipalityId.isEmpty ? null : municipalityId,
      );
    } catch (e) {
      debugPrint('[LguDebugData] demo registers purge: $e');
      return 0;
    }
  }

  /// Seeds [months] of demo DAE-1B register rows for every active lodging
  /// establishment in [municipalityId] (empty = province-wide).
  /// Existing demo months are replaced; hotel-entered rows are kept.
  static Future<LguDebugRegisterSeedResult> seedHotelRegisters({
    required String municipalityId,
    int months = 3,
    LguDebugSeedProgress? onProgress,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw StateError('Sign in as LGU tourism staff, then try again.');
    }
    final mid = normalizeMunicipalityId(municipalityId);
    final registry = await (mid.isEmpty
            ? EstablishmentApprovalService.watchAll()
            : EstablishmentApprovalService.watchForMunicipality(mid))
        .first
        .timeout(_timeout);
    final targets = [
      for (final e in registry)
        if (e.isActive && AeRegisterSchema.forCategory(e.category).tracksRooms) e,
    ];
    var seededAes = 0, totalMonths = 0, totalRows = 0, failed = 0;
    for (var i = 0; i < targets.length; i++) {
      final e = targets[i];
      onProgress?.call(i, targets.length, e.businessName);
      try {
        final doc = await _db.collection('accommodation_establishments').doc(e.id).get();
        final d = doc.data() ?? const <String, dynamic>{};
        final profile = AeRegisterProfile.fromRegistry(
          aeId: e.id,
          aeName: e.businessName,
          category: e.category,
          municipalityId: e.municipalityId.isNotEmpty ? e.municipalityId : mid,
          municipality: e.municipality,
          totalRooms: e.roomCount,
          aeType: (d['aeType'] ?? '').toString(),
          classificationCode: (d['classificationCode'] ?? '').toString(),
        );
        final r = await EstablishmentDemoSeedService.seed(
          profile: profile,
          schema: AeRegisterSchema.forCategory(e.category),
          months: months,
        );
        seededAes++;
        totalMonths += r.months;
        totalRows += r.rows;
      } catch (err) {
        failed++;
        debugPrint('[LguDebugData] register seed ${e.id}: $err');
      }
    }
    onProgress?.call(targets.length, targets.length, '');
    if (targets.isNotEmpty && seededAes == 0) {
      throw StateError(
        'Could not write demo registers. Deploy the latest firestore.rules '
        '(ae_monthly_reports) and try again.',
      );
    }
    return LguDebugRegisterSeedResult(
      establishments: seededAes,
      months: totalMonths,
      rows: totalRows,
      failed: failed,
    );
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
      await _guardWrite(batch!.commit());
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

    final groupCandidates = <({
      String uid,
      String name,
      String email,
      Map<String, dynamic> profile,
    })>[];

    for (final munId in munIds) {
      final munName = _displayName(munId);
      var spots = await _loadSpots(munId, spotIds);
      if (spots.isEmpty) {
        final hubId = '${munId}_visitor_hub';
        await _guardWrite(_db.collection('tourist_spots').doc(hubId).set({
          'name': '$munName Visitor Hub',
          'category': 'Resort',
          'municipalityId': munId,
          'municipality': munName,
          'status': 'Active',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)));
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
        groupCandidates.add((
          uid: uid,
          name: '$fn $ln',
          email: email,
          profile: {
            'uid': uid,
            'name': '$fn $ln',
            'sex': sex,
            'nationality': nationality,
            'country': country,
            'province': province,
            'city': city,
            'isLocal': isLocal,
            'localOrForeign': isLocal ? 'Local' : 'Foreign',
          },
        ));

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
            'filipinoCount': isLocal ? partySize : 0,
            'foreignCount': isLocal ? 0 : partySize,
            'touristSex': sex,
            'touristCountry': country,
            'touristProvince': province,
            'touristCity': city,
            'touristIsLocal': isLocal,
            'touristLocalOrForeign': isLocal ? 'Local' : 'Foreign',
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
            'filipinoCount': isLocal ? partySize : 0,
            'foreignCount': isLocal ? 0 : partySize,
            'checkin_time': ts,
            'seedTag': 'lgu_analytics_debug_v1',
          });

          seededCheckIns += 1;
          await commitIfNeeded();
        }
        await commitIfNeeded();
      }

      // "Laag with Friends" group check-ins: 3 members + 1 companion each,
      // on a day the members did not scan alone (so none are deduped).
      final groupDay = recentDays[checkInsPerTourist % recentDays.length];
      for (var g = 0; g < 3; g++) {
        final start = g * 4;
        if (start + 2 >= groupCandidates.length) break;
        final members = groupCandidates.sublist(start, start + 3);
        final lead = members.first;
        final spot = spots[g % spots.length];
        final ts = Timestamp.fromDate(
          DateTime(groupDay.year, groupDay.month, groupDay.day, 10 + g, 15),
        );
        final profiles = [for (final m in members) m.profile];
        final females = profiles.where((p) => p['sex'] == 'Female').length;
        final filipinos = profiles.where((p) => p['isLocal'] == true).length;
        final docId = 'seed_group_${munId}_${g + 1}';
        enqueueSet(_db.collection('qr_checkins').doc(docId), {
          'userId': lead.uid,
          'user_id': lead.uid,
          'tourist_id': lead.uid,
          'touristName': lead.name,
          'tourist_name': lead.name,
          'touristEmail': lead.email,
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
          'groupId': 'seed_group_$munId',
          'groupName': 'Seed Barkada ${g + 1}',
          'groupLeaderUid': lead.uid,
          'groupMemberUids': [for (final m in members) m.uid],
          'groupMembers': profiles,
          'companionCount': 1,
          'companionFemale': 1,
          'companionMale': 0,
          'companionFilipino': 1,
          'companionForeign': 0,
          'partySize': members.length + 1,
          'visitorCount': members.length + 1,
          'femaleCount': females + 1,
          'maleCount': members.length - females,
          'filipinoCount': filipinos + 1,
          'foreignCount': members.length - filipinos,
          'timestamp': ts,
          'createdAt': ts,
        });
        seededCheckIns += 1;
      }
      groupCandidates.clear();
      await commitIfNeeded();
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

  /// Firestore web SDK retries RESOURCE_EXHAUSTED writes forever, so a commit
  /// over the free-tier write quota never completes on its own.
  static const Duration _commitTimeout = Duration(seconds: 45);

  static const String _writeQuotaMessage =
      'Firestore is not accepting writes right now — usually the free Spark '
      'plan\'s daily write quota (20,000/day) is used up. It resets around '
      '3:00 PM PH time. Try again later, seed a single LGU, or upgrade the '
      'Firebase project to Blaze.';

  static Future<void> _guardWrite(Future<void> write) async {
    try {
      await write.timeout(_commitTimeout);
    } on TimeoutException {
      throw StateError(_writeQuotaMessage);
    } on FirebaseException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw StateError(_writeQuotaMessage);
      }
      rethrow;
    }
  }

  /// Firestore writes one seed run costs (tourist + user doc, and a
  /// qr_checkins + checkins doc per visit).
  static int estimateSeedWrites({
    required int touristsPerMunicipality,
    required int checkInsPerTourist,
    required bool seedAllMunicipalities,
  }) {
    final lgus =
        seedAllMunicipalities ? getMisamisOccidentalMunicipalities().length : 1;
    return lgus * touristsPerMunicipality * (2 + 2 * checkInsPerTourist);
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
    final registersByStatus = <String, int>{};
    var totalTourists = 0;
    var totalCheckIns = 0;
    var totalRegisters = 0;
    var registerGuestNights = 0;
    var legacyStayDocs = 0;

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
      final reports = mun.isEmpty
          ? await AeRegisterService.listInRange(start: DateTime(2000), end: DateTime(2100))
          : await AeRegisterService.listForMunicipality(mun);
      totalRegisters = reports.length;
      for (final r in reports) {
        final key = r.isDemo ? 'Demo' : (r.isSubmitted ? 'Submitted' : 'Draft');
        registersByStatus[key] = (registersByStatus[key] ?? 0) + 1;
        registerGuestNights += r.totals.guestNights;
      }
    } catch (e) {
      debugPrint('[LguDebugData] registers snapshot: $e');
    }

    for (final legacy in ['establishment_stay_requests', 'establishment_stay_reviews']) {
      try {
        final agg = await _db.collection(legacy).count().get();
        legacyStayDocs += agg.count ?? 0;
      } catch (_) {}
    }

    return LguDebugDataSnapshot(
      totalTourists: totalTourists,
      touristsByMunicipality: byMun,
      totalCheckIns: totalCheckIns,
      checkInsBySpot: bySpot,
      checkInsByMunicipality: checkInsByMun,
      totalRegisters: totalRegisters,
      registersByStatus: registersByStatus,
      registerGuestNights: registerGuestNights,
      legacyStayDocs: legacyStayDocs,
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
