import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:async' show TimeoutException;

import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/party_count_complements.dart';

/// Status for establishment stay requests (hotel / AE QR flow).
abstract final class EstablishmentStayStatus {
  static const pending = 'pending';
  static const confirmed = 'confirmed';
  static const rejected = 'rejected';
  static const checkedOut = 'checked_out';

  /// Stays that count for DOT/DAE (confirmed or already checked out).
  static bool countsForDae(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    return s == confirmed || s == checkedOut;
  }
}

class EstablishmentStayRequest {
  const EstablishmentStayRequest({
    required this.id,
    required this.establishmentId,
    required this.establishmentName,
    required this.touristId,
    required this.status,
    this.municipalityId = '',
    this.municipality = '',
    this.establishmentCategory = '',
    this.roomsAvailable,
    this.touristName = '',
    this.touristEmail = '',
    this.touristSex = '',
    this.touristNationality = '',
    this.touristCountry = '',
    this.touristProvince = '',
    this.touristCity = '',
    this.touristIsLocal,
    this.touristLocalOrForeign = '',
    this.partySize = 1,
    this.femaleCount = 0,
    this.maleCount = 0,
    this.filipinoCount = 0,
    this.foreignCount = 0,
    this.nightsStayed,
    this.roomsOccupied,
    this.roomNumbers = const [],
    this.checkInAt,
    this.checkOutAt,
    this.notes = '',
    this.createdAt,
    this.confirmedAt,
    this.confirmedByStaffUid,
    this.checkedOutAt,
    this.checkedOutByUid,
  });

  final String id;
  final String establishmentId;
  final String establishmentName;
  final String municipalityId;
  final String municipality;
  final String establishmentCategory;
  final int? roomsAvailable;
  final String touristId;
  final String touristName;
  final String touristEmail;
  final String touristSex;
  final String touristNationality;
  final String touristCountry;
  final String touristProvince;
  final String touristCity;
  final bool? touristIsLocal;
  final String touristLocalOrForeign;
  final String status;
  final int partySize;
  final int femaleCount;
  final int maleCount;
  final int filipinoCount;
  final int foreignCount;
  final int? nightsStayed;
  final int? roomsOccupied;
  final List<String> roomNumbers;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final String notes;
  final DateTime? createdAt;
  final DateTime? confirmedAt;
  final String? confirmedByStaffUid;
  final DateTime? checkedOutAt;
  final String? checkedOutByUid;

  bool get isPending => status == EstablishmentStayStatus.pending;
  bool get isConfirmed => status == EstablishmentStayStatus.confirmed;
  bool get isRejected => status == EstablishmentStayStatus.rejected;
  bool get isCheckedOut => status == EstablishmentStayStatus.checkedOut;
  bool get countsForDae => EstablishmentStayStatus.countsForDae(status);

  factory EstablishmentStayRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return EstablishmentStayRequest(
      id: doc.id,
      establishmentId: (d['establishmentId'] ?? '').toString(),
      establishmentName: (d['establishmentName'] ?? '').toString(),
      municipalityId: (d['municipalityId'] ?? '').toString(),
      municipality: (d['municipality'] ?? '').toString(),
      establishmentCategory:
          (d['establishmentCategory'] ?? d['category'] ?? d['type'] ?? '')
              .toString(),
      roomsAvailable: _asIntOrNull(d['roomsAvailable']),
      touristId: (d['touristId'] ?? '').toString(),
      touristName: (d['touristName'] ?? '').toString(),
      touristEmail: (d['touristEmail'] ?? '').toString(),
      touristSex: (d['touristSex'] ?? '').toString(),
      touristNationality: (d['touristNationality'] ?? '').toString(),
      touristCountry: (d['touristCountry'] ?? '').toString(),
      touristProvince: (d['touristProvince'] ?? '').toString(),
      touristCity: (d['touristCity'] ?? '').toString(),
      touristIsLocal: d['touristIsLocal'] is bool
          ? d['touristIsLocal'] as bool
          : null,
      touristLocalOrForeign: (d['touristLocalOrForeign'] ?? '').toString(),
      status: (d['status'] ?? EstablishmentStayStatus.pending)
          .toString()
          .toLowerCase(),
      partySize: _asInt(d['partySize'], fallback: 1),
      femaleCount: _asInt(d['femaleCount']),
      maleCount: _asInt(d['maleCount']),
      filipinoCount: _asInt(d['filipinoCount']),
      foreignCount: _asInt(d['foreignCount']),
      nightsStayed: _asIntOrNull(d['nightsStayed']),
      roomsOccupied: _asIntOrNull(d['roomsOccupied']),
      roomNumbers: _asStringList(d['roomNumbers']),
      checkInAt: _asDate(d['checkInAt']),
      checkOutAt: _asDate(d['checkOutAt']),
      notes: (d['notes'] ?? '').toString(),
      createdAt: _asDate(d['createdAt']) ?? _asDate(d['clientCreatedAt']),
      confirmedAt: _asDate(d['confirmedAt']) ?? _asDate(d['clientConfirmedAt']),
      confirmedByStaffUid: d['confirmedByStaffUid']?.toString(),
      checkedOutAt:
          _asDate(d['checkedOutAt']) ?? _asDate(d['clientCheckedOutAt']),
      checkedOutByUid: d['checkedOutByUid']?.toString(),
    );
  }

  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  static int? _asIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static List<String> _asStringList(dynamic v) {
    if (v is! List) return const [];
    return v
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}

/// Tourist scan → pending stay → establishment staff confirm → tourist receipt.
class EstablishmentStayService {
  EstablishmentStayService._();

  static const String collection = 'establishment_stay_requests';

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(collection);

  static Future<Map<String, dynamic>?> loadEstablishment(
    String establishmentId,
  ) async {
    final id = establishmentId.trim();
    if (id.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(EstablishmentRegistrationService.establishmentsCollection)
          .doc(id)
          .get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (e) {
      debugPrint('[EstStay] loadEstablishment failed: $e');
      return null;
    }
  }

  /// Loads tourist profile fields used for DOT demographics + receipt.
  static Future<Map<String, dynamic>> loadTouristProfile(String uid) async {
    final out = <String, dynamic>{
      'name': '',
      'email': FirebaseAuth.instance.currentUser?.email?.trim() ?? '',
      'sex': '',
      'nationality': '',
      'country': '',
      'province': '',
      'city': '',
      'isLocal': null,
      'localOrForeign': '',
    };
    try {
      final tourist = await FirebaseFirestore.instance
          .collection('tourists')
          .doc(uid)
          .get();
      final td = tourist.data();
      if (td != null) {
        out['name'] =
            (td['fullName'] ?? td['name'] ?? td['touristName'] ?? '')
                .toString()
                .trim();
        if ((out['email'] as String).isEmpty) {
          out['email'] = (td['email'] ?? '').toString().trim();
        }
        out['sex'] = (td['sex'] ?? '').toString().trim();
        out['nationality'] = (td['nationality'] ?? '').toString().trim();
        out['country'] = (td['country'] ?? '').toString().trim();
        out['province'] = (td['province'] ?? '').toString().trim();
        out['city'] = (td['city'] ?? '').toString().trim();
        out['isLocal'] = td['isLocal'];
        out['localOrForeign'] =
            (td['localOrForeign'] ?? '').toString().trim();
      }
      if ((out['name'] as String).isEmpty) {
        final user =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final ud = user.data();
        if (ud != null) {
          out['name'] =
              (ud['fullName'] ?? ud['name'] ?? '').toString().trim();
          if ((out['email'] as String).isEmpty) {
            out['email'] = (ud['email'] ?? '').toString().trim();
          }
        }
      }
    } catch (e) {
      debugPrint('[EstStay] tourist profile: $e');
    }
    if ((out['name'] as String).isEmpty) out['name'] = 'Tourist';
    return out;
  }

  /// Tourist creates a pending stay after scanning an establishment QR.
  static Future<EstablishmentStayRequest> createPendingStay({
    required String establishmentId,
    String? municipalityId,
    String? businessNameHint,
    String? municipalityHint,
    int partySize = 1,
    int? femaleCount,
    int? maleCount,
    int? filipinoCount,
    int? foreignCount,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (user == null || uid == null || uid.isEmpty) {
      throw StateError(
        'Sign in as a tourist to request a stay. '
        '(Firebase Auth required — local session alone is not enough.)',
      );
    }

    final tokenOk = await FirestoreAuthGate.ensureFreshIdToken(
      forceRefresh: false,
    );
    if (!tokenOk) {
      throw StateError(FirestoreAuthGate.missingAuthMessage());
    }

    final eid = establishmentId.trim();
    if (eid.isEmpty) {
      throw StateError('Invalid establishment QR (missing id).');
    }

    final est = await loadEstablishment(eid)
        .timeout(const Duration(seconds: 8), onTimeout: () => null);
    final establishmentName = (est?['businessName'] ??
            est?['name'] ??
            businessNameHint ??
            'Establishment')
        .toString()
        .trim();
    final mid = normalizeMunicipalityId(
      (est?['municipalityId'] ?? municipalityId ?? '').toString(),
    );
    final municipality = (est?['municipality'] ?? municipalityHint ?? '')
        .toString()
        .trim();
    final category =
        (est?['category'] ?? est?['type'] ?? '').toString().trim();
    final roomRaw = est?['roomCount'];
    final roomsAvailable = roomRaw is int
        ? roomRaw
        : int.tryParse(roomRaw?.toString() ?? '');

    final profile = await loadTouristProfile(uid).timeout(
      const Duration(seconds: 5),
      onTimeout: () => <String, dynamic>{
        'name': user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'Tourist',
        'email': user.email?.trim() ?? '',
        'sex': '',
        'nationality': '',
        'country': '',
        'province': '',
        'city': '',
        'isLocal': null,
        'localOrForeign': '',
      },
    );

    final party = partySize < 1 ? 1 : partySize;
    // Party of 1: prefill demographics from tourist registration.
    // Larger parties: leave zeros unless caller passed explicit counts —
    // staff confirm UI requires and auto-balances them.
    late final int male;
    late final int female;
    late final int fil;
    late final int for_;
    if (maleCount != null || femaleCount != null) {
      male = PartyCountComplements.clampKnown(party, maleCount ?? 0);
      female = femaleCount != null
          ? PartyCountComplements.clampKnown(party, femaleCount)
          : PartyCountComplements.complement(party, male);
    } else if (party == 1) {
      final sexPair = PartyCountComplements.sexPairFromLabel(
        profile['sex']?.toString(),
      );
      male = sexPair.male;
      female = sexPair.female;
    } else {
      male = 0;
      female = 0;
    }
    if (filipinoCount != null || foreignCount != null) {
      fil = PartyCountComplements.clampKnown(party, filipinoCount ?? 0);
      for_ = foreignCount != null
          ? PartyCountComplements.clampKnown(party, foreignCount)
          : PartyCountComplements.complement(party, fil);
    } else if (party == 1) {
      final resPair = PartyCountComplements.residencyPair(
        isLocal:
            profile['isLocal'] is bool ? profile['isLocal'] as bool : null,
        localOrForeign: profile['localOrForeign']?.toString(),
        country: profile['country']?.toString(),
        nationality: profile['nationality']?.toString(),
      );
      fil = resPair.filipino;
      for_ = resPair.foreign;
    } else {
      fil = 0;
      for_ = 0;
    }

    final now = DateTime.now();
    final ref = _col.doc();
    final data = <String, dynamic>{
      'establishmentId': eid,
      'establishmentName': establishmentName,
      'establishmentCategory': category,
      if (roomsAvailable != null) 'roomsAvailable': roomsAvailable,
      'municipalityId': mid,
      'municipality': municipality,
      'touristId': uid,
      'touristName': profile['name'],
      'touristEmail': profile['email'],
      'touristSex': profile['sex'],
      'touristNationality': profile['nationality'],
      'touristCountry': profile['country'],
      'touristProvince': profile['province'],
      'touristCity': profile['city'],
      if (profile['isLocal'] is bool) 'touristIsLocal': profile['isLocal'],
      'touristLocalOrForeign': profile['localOrForeign'],
      'status': EstablishmentStayStatus.pending,
      'partySize': party,
      'femaleCount': female < 0 ? 0 : female,
      'maleCount': male < 0 ? 0 : male,
      'filipinoCount': fil < 0 ? 0 : fil,
      'foreignCount': for_ < 0 ? 0 : for_,
      'qrType': 'establishment',
      'createdAt': Timestamp.fromDate(now),
      'clientCreatedAt': now.toIso8601String(),
    };

    try {
      try {
        await FirebaseFirestore.instance.enableNetwork();
      } catch (_) {}

      debugPrint(
        '[EstStay] writing pending stay ${ref.id} '
        'ae=$eid tourist=$uid',
      );
      await ref.set(data).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          throw TimeoutException('firestore-set-timeout');
        },
      );
    } on FirebaseException catch (e) {
      debugPrint('[EstStay] set FirebaseException ${e.code}: ${e.message}');
      if (e.code == 'permission-denied') {
        throw StateError(
          'Firestore blocked creating the stay (permission-denied). '
          'Sign out as tourist, sign in again, then rescan.',
        );
      }
      throw StateError('Could not save stay: ${e.code} ${e.message}');
    } on TimeoutException {
      throw StateError(
        'Stay write timed out. Usually means Firestore rejected the create '
        '(auth/rules) or the device is offline. '
        'Sign out/in as tourist, confirm Wi‑Fi, then scan again.',
      );
    }

    debugPrint('[EstStay] pending created ${ref.id} at $establishmentName');
    return EstablishmentStayRequest(
      id: ref.id,
      establishmentId: eid,
      establishmentName: establishmentName,
      establishmentCategory: category,
      roomsAvailable: roomsAvailable,
      municipalityId: mid,
      municipality: municipality,
      touristId: uid,
      touristName: (profile['name'] ?? 'Tourist').toString(),
      touristEmail: (profile['email'] ?? '').toString(),
      touristSex: (profile['sex'] ?? '').toString(),
      touristNationality: (profile['nationality'] ?? '').toString(),
      touristCountry: (profile['country'] ?? '').toString(),
      touristProvince: (profile['province'] ?? '').toString(),
      touristCity: (profile['city'] ?? '').toString(),
      touristIsLocal:
          profile['isLocal'] is bool ? profile['isLocal'] as bool : null,
      touristLocalOrForeign: (profile['localOrForeign'] ?? '').toString(),
      status: EstablishmentStayStatus.pending,
      partySize: party,
      femaleCount: female < 0 ? 0 : female,
      maleCount: male < 0 ? 0 : male,
      filipinoCount: fil < 0 ? 0 : fil,
      foreignCount: for_ < 0 ? 0 : for_,
      createdAt: now,
    );
  }

  static Stream<EstablishmentStayRequest?> watchStay(String stayId) {
    return _col.doc(stayId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return EstablishmentStayRequest.fromDoc(doc);
    });
  }

  static Future<EstablishmentStayRequest?> getStay(String stayId) async {
    final doc = await _col.doc(stayId).get();
    if (!doc.exists) return null;
    return EstablishmentStayRequest.fromDoc(doc);
  }

  /// Staff queue: all stays for this establishment (filter pending in UI).
  static Stream<List<EstablishmentStayRequest>> watchForEstablishment(
    String establishmentId,
  ) {
    return _col
        .where('establishmentId', isEqualTo: establishmentId.trim())
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(EstablishmentStayRequest.fromDoc)
          .toList()
        ..sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
      return list;
    });
  }

  static Stream<List<EstablishmentStayRequest>> watchForTourist(String touristId) {
    return _col
        .where('touristId', isEqualTo: touristId.trim())
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(EstablishmentStayRequest.fromDoc)
          .toList()
        ..sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
      return list;
    });
  }

  /// Latest pending/confirmed stay for this tourist + AE on the local calendar day.
  /// Rejected stays are ignored so a reject can rescan without a rebook prompt.
  static Future<EstablishmentStayRequest?> findTodaysStayForTourist({
    required String touristId,
    required String establishmentId,
  }) async {
    final tid = touristId.trim();
    final eid = establishmentId.trim();
    if (tid.isEmpty || eid.isEmpty) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      // Single-equality query avoids a composite index; filter AE client-side.
      final snap = await _col
          .where('touristId', isEqualTo: tid)
          .get()
          .timeout(const Duration(seconds: 8));

      EstablishmentStayRequest? best;
      DateTime? bestWhen;
      for (final doc in snap.docs) {
        final stay = EstablishmentStayRequest.fromDoc(doc);
        if (stay.establishmentId.trim() != eid) continue;
        if (!stay.isPending && !stay.isConfirmed) continue;
        final when = stay.checkInAt ?? stay.confirmedAt ?? stay.createdAt;
        if (when == null) continue;
        final day = DateTime(when.year, when.month, when.day);
        if (day != today) continue;
        if (bestWhen == null || when.isAfter(bestWhen)) {
          best = stay;
          bestWhen = when;
        }
      }
      return best;
    } on TimeoutException {
      debugPrint('[EstStay] findTodaysStay timed out');
      return null;
    } catch (e) {
      debugPrint('[EstStay] findTodaysStay failed: $e');
      return null;
    }
  }

  static Future<void> confirmStay({
    required String stayId,
    required int nightsStayed,
    required int roomsOccupied,
    required int partySize,
    required int maleCount,
    required int femaleCount,
    required int filipinoCount,
    required int foreignCount,
    DateTime? checkInAt,
    DateTime? checkOutAt,
    String notes = '',
    List<String> roomNumbers = const [],
    String? establishmentCategory,
    int? roomsAvailable,
  }) async {
    final staffUid = FirebaseAuth.instance.currentUser?.uid;
    if (staffUid == null || staffUid.isEmpty) {
      throw StateError('Staff must be signed in to confirm.');
    }
    final party = partySize < 1 ? 1 : partySize;
    final male = PartyCountComplements.clampKnown(party, maleCount);
    final female = PartyCountComplements.complement(party, male);
    final fil = PartyCountComplements.clampKnown(party, filipinoCount);
    final for_ = PartyCountComplements.complement(party, fil);

    if (!PartyCountComplements.sumsToTotal(party, male, female) ||
        !PartyCountComplements.sumsToTotal(party, fil, for_)) {
      throw StateError(
        'Party demographics must sum to party size '
        '(Male+Female and Filipino+Foreign).',
      );
    }

    final now = DateTime.now();
    final nights = nightsStayed < 0 ? 0 : nightsStayed;
    final rooms = roomsOccupied < 0 ? 0 : roomsOccupied;
    final checkout = checkOutAt ??
        (nights > 0
            ? (checkInAt ?? now).add(Duration(days: nights))
            : null);

    final patch = <String, dynamic>{
      'status': EstablishmentStayStatus.confirmed,
      'nightsStayed': nights,
      'roomsOccupied': rooms,
      'partySize': party,
      'maleCount': male,
      'femaleCount': female,
      'filipinoCount': fil,
      'foreignCount': for_,
      'roomNumbers': roomNumbers
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'notes': notes.trim(),
      'confirmedAt': FieldValue.serverTimestamp(),
      'clientConfirmedAt': now.toIso8601String(),
      'confirmedByStaffUid': staffUid,
      'checkInAt': Timestamp.fromDate(checkInAt ?? now),
      if (checkout != null) 'checkOutAt': Timestamp.fromDate(checkout),
      if (establishmentCategory != null &&
          establishmentCategory.trim().isNotEmpty)
        'establishmentCategory': establishmentCategory.trim(),
      if (roomsAvailable != null) 'roomsAvailable': roomsAvailable,
    };
    await _col.doc(stayId).update(patch);
    debugPrint('[EstStay] confirmed $stayId by $staffUid');
  }

  static Future<void> rejectStay({
    required String stayId,
    String notes = '',
  }) async {
    final staffUid = FirebaseAuth.instance.currentUser?.uid;
    if (staffUid == null || staffUid.isEmpty) {
      throw StateError('Staff must be signed in to reject.');
    }
    await _col.doc(stayId).update({
      'status': EstablishmentStayStatus.rejected,
      'notes': notes.trim(),
      'confirmedAt': FieldValue.serverTimestamp(),
      'clientConfirmedAt': DateTime.now().toIso8601String(),
      'confirmedByStaffUid': staffUid,
    });
  }

  /// Ends an in-house stay and frees assigned rooms. Tourist or AE staff.
  static Future<void> checkOutStay({
    required String stayId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to check out.');
    }
    final existing = await getStay(stayId);
    if (existing == null) {
      throw StateError('Stay not found.');
    }
    if (!existing.isConfirmed) {
      throw StateError(
        existing.isCheckedOut
            ? 'This stay is already checked out.'
            : 'Only confirmed stays can be checked out.',
      );
    }
    if (existing.touristId != uid && existing.establishmentId != uid) {
      throw StateError('You cannot check out this stay.');
    }
    final now = DateTime.now();
    await _col.doc(stayId).update({
      'status': EstablishmentStayStatus.checkedOut,
      'checkedOutAt': FieldValue.serverTimestamp(),
      'clientCheckedOutAt': now.toIso8601String(),
      'checkedOutByUid': uid,
    });
    debugPrint('[EstStay] checked out $stayId by $uid');
  }

  static bool isLodgingCategory(String? category) =>
      EstablishmentCapability.isLodging(category);
}
