import 'package:atmos_trs_system/config/beta_testing_config.dart';
import 'package:atmos_trs_system/models/tourist_group.dart';
import 'package:atmos_trs_system/services/qr_checkin_service.dart';
import 'package:atmos_trs_system/services/qr_scan_demo_guard.dart';
import 'package:atmos_trs_system/services/tourist_group_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/utils/checkin_visitor_expansion.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// One destination scan by the group leader, stored as one visit per member.
class LaagGroupCheckInResult {
  const LaagGroupCheckInResult({
    required this.checkedIn,
    required this.skipped,
    required this.spotName,
  });

  final int checkedIn;
  final int skipped;
  final String spotName;

  String get message {
    if (checkedIn == 0 && skipped > 0) {
      return 'Everyone in the group is already checked in at $spotName today.';
    }
    final skip = skipped == 0
        ? ''
        : ' $skipped already checked in today and were skipped.';
    return 'Checked in $checkedIn member${checkedIn == 1 ? '' : 's'} at $spotName.$skip';
  }
}

/// Separate from the individual QR check-in. Does not change party size.
class LaagGroupCheckInService {
  LaagGroupCheckInService._();

  static Future<LaagGroupCheckInResult> checkInGroup({
    required TouristGroup group,
    required String spotId,
    String? municipalityId,
    double? qrLat,
    double? qrLng,
    bool isDemoQr = false,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw const TouristGroupException('Please log in to check in your group.');
    }
    if (!group.isLeader(uid)) {
      throw const TouristGroupException(
        'Only the group leader can check in the group.',
      );
    }
    if (!group.isActive) {
      throw const TouristGroupException(
        'This group has ended. Create a new one to check in together.',
      );
    }
    final participants = group.participatingMembers;
    if (participants.isEmpty) {
      throw const TouristGroupException(
        'No one has accepted the group invitation yet.',
      );
    }

    final spot = await QRCheckInService.getSpotById(
      spotId,
      municipalityId: municipalityId,
    );
    if (spot == null) {
      throw const TouristGroupException(
        'This destination QR is not a registered tourist spot.',
      );
    }
    var municipality = spot.municipalityId.isNotEmpty
        ? spot.municipalityId
        : normalizeMunicipalityId(municipalityId ?? '');
    if (municipality.isEmpty) {
      throw const TouristGroupException(
        'This spot has no municipality set.',
      );
    }
    if (!BetaTestingGuard.bypassValidation &&
        !isMisamisOccidentalMunicipalityId(municipality)) {
      throw const TouristGroupException(
        'Group check-in is only available in Misamis Occidental.',
      );
    }
    final demoBlock = QrScanDemoGuard.municipalityRestrictionMessage(municipality);
    if (demoBlock != null) {
      throw TouristGroupException(demoBlock);
    }
    if (spot.latitude != null && spot.longitude != null) {
      final mismatch = QRCheckInService.verifyQrCoordinatesMatchFirestore(
        qrLat: qrLat,
        qrLng: qrLng,
        firestoreLat: spot.latitude!,
        firestoreLng: spot.longitude!,
        spotId: spot.spotId,
        spotName: spot.spotName,
      );
      if (mismatch != null) throw TouristGroupException(mismatch);
    }
    if (!isDemoQr &&
        !BetaTestingGuard.bypassValidation &&
        spot.latitude != null &&
        spot.longitude != null &&
        spot.latitude!.abs() > 1e-7 &&
        spot.longitude!.abs() > 1e-7) {
      final gps = await QRCheckInService.verifyProximityToTouristSpot(
        latitude: spot.latitude!,
        longitude: spot.longitude!,
        spotLabel: spot.spotName.isNotEmpty ? spot.spotName : spot.spotId,
        spotId: spot.spotId,
        spotName: spot.spotName,
      );
      if (gps != null) throw TouristGroupException(gps);
    }

    final routed = BetaTestingGuard.applyCheckInRouting(
      municipalityId: municipality,
      municipality: spot.municipality,
      spotId: spot.spotId,
      spotName: spot.spotName,
    );
    municipality = routed.municipalityId;
    final locationId = routed.spotId;
    final spotName = routed.spotName.isNotEmpty ? routed.spotName : spot.spotName;
    final placeLabel = spotName.isNotEmpty ? spotName : locationId;

    final db = FirebaseFirestore.instance;
    final already = await Future.wait([
      for (final member in participants)
        _alreadyCheckedInToday(db, member.uid, locationId),
    ]);
    final ready = <TouristGroupMember>[];
    var skipped = 0;
    for (var i = 0; i < participants.length; i++) {
      if (already[i]) {
        skipped++;
      } else {
        ready.add(participants[i]);
      }
    }
    if (ready.isEmpty) {
      return LaagGroupCheckInResult(
        checkedIn: 0,
        skipped: skipped,
        spotName: placeLabel,
      );
    }

    final batch = db.batch();
    final notices = <String, Map<String, dynamic>>{};
    final day = _dayKey(DateTime.now());
    for (final member in ready) {
      final ref = db.collection('qr_checkins').doc();
      final profile = member.toProfileMap();
      final female = member.sex.toLowerCase().startsWith('f') ? 1 : 0;
      final male = member.sex.toLowerCase().startsWith('m') ? 1 : 0;
      final knownHome = profile['nationality'].toString().isNotEmpty ||
          profile['country'].toString().isNotEmpty ||
          profile['localOrForeign'].toString().isNotEmpty ||
          profile['isLocal'] is bool;
      final domestic = knownHome && isDomesticVisitorProfile(profile);
      final noticeId = 'laag_${group.id}_${locationId}_${member.uid}_$day';
      batch.set(ref, {
        'userId': member.uid,
        'user_id': member.uid,
        'tourist_id': member.uid,
        'touristName': member.name,
        'tourist_name': member.name,
        if (member.name.isNotEmpty) 'touristFullName': member.name,
        if (member.sex.isNotEmpty) 'touristSex': member.sex,
        if (member.nationality.isNotEmpty) 'touristNationality': member.nationality,
        if (member.country.isNotEmpty) 'touristCountry': member.country,
        if (member.province.isNotEmpty) 'touristProvince': member.province,
        if (member.city.isNotEmpty) 'touristCity': member.city,
        if (member.isLocal != null) 'touristIsLocal': member.isLocal,
        if (member.localOrForeign.isNotEmpty)
          'touristLocalOrForeign': member.localOrForeign,
        'municipalityId': municipality,
        'lguId': municipality,
        'spotId': locationId,
        'spot_id': locationId,
        'touristSpotId': locationId,
        'spot_name': spotName,
        'spotName': spotName,
        'location': placeLabel,
        'municipality': routed.municipality,
        'status': 'Verified',
        'source': 'laag_group',
        'groupId': group.id,
        'groupName': group.name,
        'groupLeaderUid': group.leaderUid,
        'partySize': 1,
        'visitorCount': 1,
        'femaleCount': female,
        'maleCount': male,
        'filipinoCount': domestic ? 1 : 0,
        'foreignCount': knownHome && !domestic ? 1 : 0,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      notices[noticeId] = {
        'uid': member.uid,
        'title': 'Checked in with ${group.name}',
        'message': 'You were checked in at $placeLabel.',
        'spotId': locationId,
        'spotName': placeLabel,
      };
    }
    await batch.commit();
    try {
      await db.collection(TouristGroup.collection).doc(group.id).update({
        for (final entry in notices.entries) 'notices.${entry.key}': entry.value,
      });
    } catch (_) {}

    if (ready.any((m) => m.uid == uid)) {
      try {
        await db.collection('tourists').doc(uid).set({
          'lastCheckInAt': FieldValue.serverTimestamp(),
          'lastCheckInLguId': municipality,
          'lastCheckInSpotId': locationId,
        }, SetOptions(merge: true));
      } catch (_) {}
      await UserActivityService.syncVisitedSpotsFromQrCheckins();
      await UserActivityService.addNotificationIfAbsent(
        id: 'laag_${group.id}_${locationId}_${uid}_$day',
        title: 'Checked in with ${group.name}',
        message: 'You were checked in at $placeLabel.',
        type: NotificationType.checkin,
      );
    }
    await TouristGroupService.deliverMyCheckInNotices();

    return LaagGroupCheckInResult(
      checkedIn: ready.length,
      skipped: skipped,
      spotName: placeLabel,
    );
  }

  static Future<bool> _alreadyCheckedInToday(
    FirebaseFirestore db,
    String userId,
    String spotId,
  ) async {
    try {
      final snap = await db
          .collection('qr_checkins')
          .where('userId', isEqualTo: userId)
          .limit(40)
          .get();
      final today = DateTime.now();
      for (final doc in snap.docs) {
        final data = doc.data();
        final id = (data['spotId'] ?? data['spot_id'] ?? '').toString();
        if (id != spotId) continue;
        final stamp = data['timestamp'] ?? data['createdAt'];
        if (stamp is Timestamp && _sameDay(stamp.toDate(), today)) return true;
      }
    } catch (_) {}
    return false;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayKey(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}
