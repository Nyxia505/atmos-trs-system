import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atmos_trs_system/services/establishment_stay_review_service.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';
import 'package:atmos_trs_system/utils/establishment_room_grid.dart';

/// Result of a demo seed / clear run.
class EstablishmentDemoSeedResult {
  const EstablishmentDemoSeedResult({
    this.inHouse = 0,
    this.checkedOut = 0,
    this.pending = 0,
    this.rejected = 0,
    this.reviews = 0,
    this.removedStays = 0,
    this.removedReviews = 0,
    this.skippedReviews = 0,
  });

  final int inHouse;
  final int checkedOut;
  final int pending;
  final int rejected;
  final int reviews;
  final int removedStays;
  final int removedReviews;

  /// Demo reviews this account may not delete (authored by another account).
  final int skippedReviews;

  int get total => inHouse + checkedOut + pending + rejected;
}

/// Seeds / removes demo stays + reviews for the signed-in establishment so
/// staff can preview the dashboard. Every doc is tagged `seed: 'demo'`;
/// [clear] removes only those, leaving real guest data untouched.
///
/// Rules path: the establishment account creates each request as `pending`
/// (touristId = own uid), then confirms / rejects / checks out as staff.
abstract final class EstablishmentDemoSeedService {
  static const String seedTag = 'demo';
  static const int minCount = 5;
  static const int maxCount = 100;
  static const int _batchLimit = 400;

  static CollectionReference<Map<String, dynamic>> get _stays =>
      FirebaseFirestore.instance.collection(EstablishmentStayService.collection);

  static CollectionReference<Map<String, dynamic>> get _reviews =>
      FirebaseFirestore.instance
          .collection(EstablishmentStayReviewService.collection);

  static String _requireUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw StateError('Sign in again to manage demo data.');
    }
    return uid;
  }

  /// Status mix for [count] stays; in-house capped by free [enabledRooms].
  static EstablishmentDemoSeedResult plan(int count, int enabledRooms) {
    final n = count.clamp(minCount, maxCount);
    final inHouse = math.min(math.max(1, (n * 0.15).round()), enabledRooms);
    final pending = math.max(1, (n * 0.1).round());
    final rejected = (n * 0.07).round();
    return EstablishmentDemoSeedResult(
      inHouse: inHouse,
      pending: pending,
      rejected: rejected,
      checkedOut: math.max(0, n - inHouse - pending - rejected),
    );
  }

  /// Replaces any previous demo set with [count] new demo stays.
  static Future<EstablishmentDemoSeedResult> seed({
    required int count,
    required String establishmentName,
    required String municipality,
    required String municipalityId,
    required String category,
    required int roomCount,
    List<String> disabledRooms = const [],
  }) async {
    final uid = _requireUid();
    await FirestoreAuthGate.ensureFreshIdToken();
    final cleared = await clear();

    final n = count.clamp(minCount, maxCount);
    final rnd = math.Random();
    final now = DateTime.now();

    final disabled = <String>{
      for (final d in disabledRooms)
        if (EstablishmentRoomGrid.normalizeSlotId(d, roomCount) != null)
          EstablishmentRoomGrid.normalizeSlotId(d, roomCount)!,
    };
    final enabledRooms = [
      for (var i = 1; i <= roomCount; i++)
        if (!disabled.contains('$i')) '$i',
    ];

    final mix = plan(n, enabledRooms.length);
    final inHouse = mix.inHouse;
    final pending = mix.pending;
    final rejected = mix.rejected;
    final checkedOut = mix.checkedOut;

    final plans = <_DemoStay>[];
    final freeForInHouse = [...enabledRooms]..shuffle(rnd);

    for (var i = 0; i < inHouse; i++) {
      final daysAgo = rnd.nextInt(3);
      plans.add(_DemoStay(
        kind: _Kind.inHouse,
        guest: _guest(rnd),
        daysAgo: daysAgo,
        nights: daysAgo + 1 + rnd.nextInt(3),
        rooms: [freeForInHouse.removeLast()],
      ));
    }
    for (var i = 0; i < checkedOut; i++) {
      // Skew toward recent days so 7/14-day trends look alive.
      final daysAgo = 1 + (math.pow(rnd.nextDouble(), 1.6) * 29).floor();
      final nights = 1 + rnd.nextInt(math.min(3, daysAgo));
      final guest = _guest(rnd);
      final rooms = <String>[];
      if (enabledRooms.isNotEmpty) {
        rooms.add(enabledRooms[rnd.nextInt(enabledRooms.length)]);
        if (guest.party >= 4 && enabledRooms.length > 1 && rnd.nextBool()) {
          final second = enabledRooms[rnd.nextInt(enabledRooms.length)];
          if (!rooms.contains(second)) rooms.add(second);
        }
      }
      plans.add(_DemoStay(
        kind: _Kind.checkedOut,
        guest: guest,
        daysAgo: daysAgo,
        nights: nights,
        rooms: rooms,
        review: rnd.nextDouble() < 0.45 ? _review(rnd) : null,
      ));
    }
    for (var i = 0; i < pending; i++) {
      plans.add(_DemoStay(
        kind: _Kind.pending,
        guest: _guest(rnd),
        daysAgo: 0,
        minutesAgo: 5 + rnd.nextInt(240),
      ));
    }
    for (var i = 0; i < rejected; i++) {
      plans.add(_DemoStay(
        kind: _Kind.rejected,
        guest: _guest(rnd),
        daysAgo: 1 + rnd.nextInt(25),
      ));
    }

    for (final p in plans) {
      p.checkIn = p.daysAgo == 0
          ? now.subtract(Duration(minutes: p.minutesAgo ?? 30 + rnd.nextInt(240)))
          : DateTime(now.year, now.month, now.day - p.daysAgo, 13 + rnd.nextInt(5),
              rnd.nextInt(60));
      p.ref = _stays.doc();
    }

    // 1) Create every request as pending (tourist-create rule).
    await _commitChunks(plans, (batch, p) {
      final g = p.guest;
      final fil = g.local ? g.party : 0;
      final prefill = g.party == 1 || p.kind != _Kind.pending;
      final created = p.kind == _Kind.pending
          ? p.checkIn
          : p.checkIn.subtract(const Duration(minutes: 20));
      batch.set(p.ref, {
        'establishmentId': uid,
        'establishmentName': establishmentName,
        'establishmentCategory': category,
        if (roomCount > 0) 'roomsAvailable': roomCount,
        'municipalityId': municipalityId,
        'municipality': municipality,
        'touristId': uid,
        'touristName': g.name,
        'touristEmail': '',
        'touristSex': g.sex,
        'touristNationality': g.nationality,
        'touristCountry': g.country,
        'touristProvince': g.province,
        'touristCity': g.city,
        'touristIsLocal': g.local,
        'touristLocalOrForeign': g.local ? 'Local' : 'Foreign',
        'status': EstablishmentStayStatus.pending,
        'partySize': g.party,
        'maleCount': prefill ? g.male : 0,
        'femaleCount': prefill ? g.party - g.male : 0,
        'filipinoCount': prefill ? fil : 0,
        'foreignCount': prefill ? g.party - fil : 0,
        'qrType': 'establishment',
        'createdAt': Timestamp.fromDate(created),
        'clientCreatedAt': created.toIso8601String(),
        'seed': seedTag,
      });
    });

    // 2) Staff desk: confirm / check out / reject.
    await _commitChunks(
      plans.where((p) => p.kind != _Kind.pending).toList(),
      (batch, p) {
        final confirmedAt = p.checkIn.add(const Duration(minutes: 10));
        if (p.kind == _Kind.rejected) {
          batch.update(p.ref, {
            'status': EstablishmentStayStatus.rejected,
            'notes': 'Fully booked for requested date.',
            'confirmedAt': Timestamp.fromDate(confirmedAt),
            'clientConfirmedAt': confirmedAt.toIso8601String(),
            'confirmedByStaffUid': uid,
          });
          return;
        }
        final g = p.guest;
        final fil = g.local ? g.party : 0;
        final checkOut = DateTime(p.checkIn.year, p.checkIn.month,
            p.checkIn.day + p.nights, p.checkIn.hour, p.checkIn.minute);
        final patch = <String, dynamic>{
          'status': EstablishmentStayStatus.confirmed,
          'nightsStayed': p.nights,
          'roomsOccupied': p.rooms.isEmpty ? 1 : p.rooms.length,
          'partySize': g.party,
          'maleCount': g.male,
          'femaleCount': g.party - g.male,
          'filipinoCount': fil,
          'foreignCount': g.party - fil,
          'roomNumbers': p.rooms,
          'notes': '',
          'confirmedAt': Timestamp.fromDate(confirmedAt),
          'clientConfirmedAt': confirmedAt.toIso8601String(),
          'confirmedByStaffUid': uid,
          'checkInAt': Timestamp.fromDate(p.checkIn),
          'checkOutAt': Timestamp.fromDate(checkOut),
        };
        if (p.kind == _Kind.checkedOut) {
          final outAt =
              DateTime(checkOut.year, checkOut.month, checkOut.day, 11);
          p.checkedOutAt = outAt;
          patch.addAll({
            'status': EstablishmentStayStatus.checkedOut,
            'checkedOutAt': Timestamp.fromDate(outAt),
            'clientCheckedOutAt': outAt.toIso8601String(),
            'checkedOutByUid': uid,
          });
        }
        batch.update(p.ref, patch);
      },
    );

    // 3) Reviews on some checked-out stays.
    final reviewed = plans.where((p) => p.review != null).toList();
    await _commitChunks(reviewed, (batch, p) {
      final r = p.review!;
      final at = (p.checkedOutAt ?? p.checkIn).add(const Duration(minutes: 90));
      batch.set(_reviews.doc(), {
        'stayRequestId': p.ref.id,
        'establishmentId': uid,
        'touristId': uid,
        'userId': uid,
        'authorName': p.guest.name,
        'establishmentName': establishmentName,
        'roomNumbers': p.rooms,
        'hotelRating': r.hotel,
        'roomRating': r.room,
        'comment': r.comment,
        'createdAt': Timestamp.fromDate(at),
        'seed': seedTag,
      });
    });

    debugPrint('[DemoSeed] seeded ${plans.length} stays for $uid');
    return EstablishmentDemoSeedResult(
      inHouse: inHouse,
      checkedOut: checkedOut,
      pending: pending,
      rejected: rejected,
      reviews: reviewed.length,
      removedStays: cleared.removedStays,
      removedReviews: cleared.removedReviews,
      skippedReviews: cleared.skippedReviews,
    );
  }

  /// Deletes every `seed == 'demo'` stay + review for this establishment.
  static Future<EstablishmentDemoSeedResult> clear() async {
    final uid = _requireUid();
    await FirestoreAuthGate.ensureFreshIdToken();

    final staySnap =
        await _stays.where('establishmentId', isEqualTo: uid).get();
    final stayRefs = [
      for (final d in staySnap.docs)
        if (d.data()['seed'] == seedTag) d.reference,
    ];
    await _commitChunks(stayRefs, (batch, ref) => batch.delete(ref));

    final reviewSnap =
        await _reviews.where('establishmentId', isEqualTo: uid).get();
    final ownReviews = <DocumentReference<Map<String, dynamic>>>[];
    var skipped = 0;
    for (final d in reviewSnap.docs) {
      final data = d.data();
      if (data['seed'] != seedTag) continue;
      if (data['touristId'] == uid) {
        ownReviews.add(d.reference);
      } else {
        skipped++;
      }
    }
    await _commitChunks(ownReviews, (batch, ref) => batch.delete(ref));

    return EstablishmentDemoSeedResult(
      removedStays: stayRefs.length,
      removedReviews: ownReviews.length,
      skippedReviews: skipped,
    );
  }

  static Future<void> _commitChunks<T>(
    List<T> items,
    void Function(WriteBatch batch, T item) write,
  ) async {
    for (var i = 0; i < items.length; i += _batchLimit) {
      final batch = FirebaseFirestore.instance.batch();
      for (final item in items.skip(i).take(_batchLimit)) {
        write(batch, item);
      }
      await batch.commit();
    }
  }

  static _DemoGuest _guest(math.Random rnd) {
    if (rnd.nextDouble() < 0.7) {
      final (first, sex) = _phFirst[rnd.nextInt(_phFirst.length)];
      final last = _phLast[rnd.nextInt(_phLast.length)];
      final (province, city) = _phPlaces[rnd.nextInt(_phPlaces.length)];
      return _DemoGuest.build(rnd,
          name: '$first $last',
          sex: sex,
          nationality: 'Filipino',
          country: 'Philippines',
          province: province,
          city: city,
          local: true);
    }
    final (first, last, sex, nationality, country) =
        _foreign[rnd.nextInt(_foreign.length)];
    return _DemoGuest.build(rnd,
        name: '$first $last',
        sex: sex,
        nationality: nationality,
        country: country,
        province: '',
        city: '',
        local: false);
  }

  static _DemoReview _review(math.Random rnd) {
    final (hotel, room, comment) = _reviewPool[rnd.nextInt(_reviewPool.length)];
    return _DemoReview(hotel, room, comment);
  }

  static const _phFirst = <(String, String)>[
    ('Maria', 'Female'), ('Juan', 'Male'), ('Ana', 'Female'), ('Jose', 'Male'),
    ('Grace', 'Female'), ('Mark', 'Male'), ('Joy', 'Female'), ('Paolo', 'Male'),
    ('Rhea', 'Female'), ('Daniel', 'Male'), ('Bea', 'Female'), ('Ramon', 'Male'),
    ('Lea', 'Female'), ('Carlo', 'Male'), ('Mika', 'Female'), ('Arnel', 'Male'),
    ('Angelica', 'Female'), ('Rafael', 'Male'), ('Kristine', 'Female'),
    ('Miguel', 'Male'),
  ];

  static const _phLast = <String>[
    'Santos', 'Dela Cruz', 'Reyes', 'Mendoza', 'Lim', 'Villanueva', 'Bautista',
    'Ramos', 'Fernandez', 'Cruz', 'Aquino', 'Castillo', 'Navarro', 'Torres',
    'Gomez', 'Uy', 'Lopez', 'Garcia', 'Tan', 'Flores',
  ];

  static const _phPlaces = <(String, String)>[
    ('Misamis Occidental', 'Oroquieta City'),
    ('Misamis Occidental', 'Ozamiz City'),
    ('Misamis Occidental', 'Tangub City'),
    ('Misamis Oriental', 'Cagayan de Oro City'),
    ('Lanao del Norte', 'Iligan City'),
    ('Zamboanga del Norte', 'Dipolog City'),
    ('Cebu', 'Cebu City'),
    ('Metro Manila', 'Quezon City'),
    ('Davao del Sur', 'Davao City'),
    ('Bohol', 'Tagbilaran City'),
  ];

  static const _foreign = <(String, String, String, String, String)>[
    ('Emily', 'Carter', 'Female', 'American', 'United States'),
    ('Hiro', 'Tanaka', 'Male', 'Japanese', 'Japan'),
    ('Liam', "O'Brien", 'Male', 'Irish', 'Ireland'),
    ('Sofia', 'Garcia', 'Female', 'Spanish', 'Spain'),
    ('Ji-woo', 'Kim', 'Female', 'Korean', 'South Korea'),
    ('Noah', 'Schmidt', 'Male', 'German', 'Germany'),
    ('Chloe', 'Martin', 'Female', 'French', 'France'),
    ('Ethan', 'Brown', 'Male', 'Australian', 'Australia'),
    ('Olivia', 'Wilson', 'Female', 'British', 'United Kingdom'),
    ('Wei', 'Chen', 'Male', 'Chinese', 'China'),
  ];

  static const _reviewPool = <(int, int, String)>[
    (5, 5, 'Clean room and very friendly front desk. Will be back!'),
    (4, 4, 'Comfortable bed, quick check-in.'),
    (5, 4, 'Great location near the plaza. Aircon a bit noisy.'),
    (4, 5, 'Family room was spacious for the kids.'),
    (5, 5, 'Lovely staff, breakfast was excellent.'),
    (3, 4, 'Room was nice but WiFi was slow in the evening.'),
    (4, 3, 'Good value for the price.'),
    (5, 5, 'Quiet, spotless and the view was beautiful.'),
    (3, 3, 'Okay stay, hot water took a while.'),
  ];
}

enum _Kind { inHouse, checkedOut, pending, rejected }

class _DemoGuest {
  const _DemoGuest({
    required this.name,
    required this.sex,
    required this.nationality,
    required this.country,
    required this.province,
    required this.city,
    required this.local,
    required this.party,
    required this.male,
  });

  factory _DemoGuest.build(
    math.Random rnd, {
    required String name,
    required String sex,
    required String nationality,
    required String country,
    required String province,
    required String city,
    required bool local,
  }) {
    const sizes = [1, 1, 2, 2, 2, 2, 3, 3, 4, 5];
    final party = sizes[rnd.nextInt(sizes.length)];
    final male = party == 1
        ? (sex == 'Male' ? 1 : 0)
        : rnd.nextInt(party + 1);
    return _DemoGuest(
      name: name,
      sex: sex,
      nationality: nationality,
      country: country,
      province: province,
      city: city,
      local: local,
      party: party,
      male: male,
    );
  }

  final String name;
  final String sex;
  final String nationality;
  final String country;
  final String province;
  final String city;
  final bool local;
  final int party;
  final int male;
}

class _DemoReview {
  const _DemoReview(this.hotel, this.room, this.comment);
  final int hotel;
  final int room;
  final String comment;
}

class _DemoStay {
  _DemoStay({
    required this.kind,
    required this.guest,
    required this.daysAgo,
    this.nights = 0,
    this.rooms = const [],
    this.minutesAgo,
    this.review,
  });

  final _Kind kind;
  final _DemoGuest guest;
  final int daysAgo;
  final int nights;
  final List<String> rooms;
  final int? minutesAgo;
  final _DemoReview? review;

  late DateTime checkIn;
  late DocumentReference<Map<String, dynamic>> ref;
  DateTime? checkedOutAt;
}
