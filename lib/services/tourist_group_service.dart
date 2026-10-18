import 'dart:math';

import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/models/tourist_group.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown with a tourist-friendly message when a group action fails.
class TouristGroupException implements Exception {
  const TouristGroupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// "Laag with Friends" groups: create, join by QR / code, leave, end.
///
/// Runs fully client-side (no Cloud Functions). Firestore rules only let a
/// tourist add or remove themselves, and only the leader manage the group.
class TouristGroupService {
  TouristGroupService._();

  static const String _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(TouristGroup.collection);

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static String _requireUid() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      throw const TouristGroupException('Please log in to use Laag with Friends.');
    }
    return uid;
  }

  static String generateJoinCode() {
    final r = Random.secure();
    return List.generate(
      6,
      (_) => _codeAlphabet[r.nextInt(_codeAlphabet.length)],
    ).join();
  }

  /// Normalizes typed codes (`laag-4k2p9x` → `4K2P9X`).
  static String normalizeCode(String raw) {
    var s = raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (s.startsWith('LAAG') && s.length > 6) s = s.substring(4);
    return s;
  }

  /// The signed-in tourist's demographic snapshot from `tourists/{uid}`.
  static Future<TouristGroupMember> _selfSnapshot(String uid) async {
    final cached = UserProfileStorage.cachedProfile;
    final fallbackName = (cached?.fullName.trim().isNotEmpty ?? false)
        ? cached!.fullName.trim()
        : (FirebaseAuth.instance.currentUser?.email ?? 'Tourist')
            .split('@')
            .first;
    try {
      final snap = await _db.collection('tourists').doc(uid).get();
      final data = snap.data();
      if (data != null) {
        return TouristGroupMember.fromTouristDoc(
          uid,
          data,
          fallbackName: fallbackName,
        );
      }
    } catch (e) {
      debugPrint('[TouristGroup] tourist profile read skipped: $e');
    }
    return TouristGroupMember(
      uid: uid,
      name: fallbackName,
      sex: cached?.sex ?? '',
      nationality: cached?.nationality ?? '',
      country: cached?.country ?? '',
      province: cached?.province ?? '',
      city: cached?.city ?? '',
    );
  }

  static Future<List<TouristGroup>> _groupsWithMember(String uid) async {
    final snap = await _col
        .where('memberUids', arrayContains: uid)
        .where('status', isEqualTo: 'active')
        .limit(5)
        .get();
    return snap.docs.map(TouristGroup.fromDoc).toList();
  }

  /// Ends expired groups I lead and leaves expired groups I joined.
  static Future<void> _cleanupExpired(String uid, List<TouristGroup> groups) async {
    for (final g in groups.where((g) => g.isExpired)) {
      try {
        if (g.isLeader(uid)) {
          await _col.doc(g.id).update({'status': 'expired'});
        } else {
          await _leaveDoc(g.id, uid);
        }
      } catch (e) {
        debugPrint('[TouristGroup] cleanup ${g.id} skipped: $e');
      }
    }
  }

  /// The group I currently belong to (newest active one), or null.
  static Future<TouristGroup?> myActiveGroup() async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return null;
    try {
      final groups = await _groupsWithMember(uid);
      await _cleanupExpired(uid, groups);
      final active = groups.where((g) => g.isActive).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
      return active.isEmpty ? null : active.first;
    } catch (e) {
      debugPrint('[TouristGroup] active group lookup failed: $e');
      return null;
    }
  }

  /// Live updates of my active group (members joining / leaving).
  static Stream<TouristGroup?> watchMyActiveGroup() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return Stream.value(null);
    return _col
        .where('memberUids', arrayContains: uid)
        .where('status', isEqualTo: 'active')
        .limit(5)
        .snapshots()
        .map((snap) {
      final active = snap.docs
          .map(TouristGroup.fromDoc)
          .where((g) => g.isActive)
          .toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0)));
      return active.isEmpty ? null : active.first;
    });
  }

  /// Creates a new group led by me (leaves / ends any current group first).
  static Future<TouristGroup> createGroup(String name) async {
    final uid = _requireUid();
    final trimmed = name.trim().isEmpty ? 'My Laag Group' : name.trim();
    await _exitCurrentGroups(uid);
    final me = await _selfSnapshot(uid);
    final ref = _col.doc();
    final expires = DateTime.now().add(TouristGroup.lifetime);
    await ref.set({
      'leaderUid': uid,
      'name': trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed,
      'joinCode': generateJoinCode(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expires),
      'memberUids': [uid],
      'members': {uid: me.toGroupMap()},
    });
    return TouristGroup.fromDoc(await ref.get());
  }

  /// Finds an active group by its 6-character code.
  static Future<TouristGroup?> findByCode(String rawCode) async {
    final code = normalizeCode(rawCode);
    if (code.length != 6) return null;
    final snap = await _col.where('joinCode', isEqualTo: code).limit(5).get();
    for (final d in snap.docs) {
      final g = TouristGroup.fromDoc(d);
      if (g.isActive) return g;
    }
    return null;
  }

  /// Loads a group from a scanned group QR, verifying its code.
  static Future<TouristGroup?> findByQr(String groupId, String code) async {
    final doc = await _col.doc(groupId).get();
    if (!doc.exists) return null;
    final g = TouristGroup.fromDoc(doc);
    if (g.joinCode.toUpperCase() != normalizeCode(code)) return null;
    return g;
  }

  /// Registered tourist account for a Tourist ID or personal tourist QR.
  static Future<({String uid, TouristGroupMember member})?> lookupRegisteredTourist(
    String raw,
  ) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    var touristId = trimmed;
    if (trimmed.startsWith('{')) {
      try {
        final decoded = trimmed;
        final idMatch = RegExp(
          '"tourist_id"\\s*:\\s*"([^"]+)"',
          caseSensitive: false,
        ).firstMatch(decoded);
        touristId = idMatch?.group(1)?.trim() ?? trimmed;
      } catch (_) {}
    }
    final code = touristId.trim();
    if (code.isEmpty) return null;

    Future<({String uid, TouristGroupMember member})?> fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
    ) async {
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final role = (data['role'] ?? 'tourist').toString().trim().toLowerCase();
      if (role.isNotEmpty && role != 'tourist') return null;
      final member = TouristGroupMember.fromTouristDoc(doc.id, data);
      if (member.name.isEmpty && member.touristId.isEmpty) return null;
      return (uid: doc.id, member: member);
    }

    final byId = await _db
        .collection('tourists')
        .where('touristId', isEqualTo: code)
        .limit(1)
        .get();
    if (byId.docs.isNotEmpty) {
      return fromDoc(byId.docs.first);
    }
    if (!code.contains('-') && code.length >= 20) {
      return fromDoc(await _db.collection('tourists').doc(code).get());
    }
    return null;
  }

  /// Leader invites a registered tourist. They must accept before check-in.
  static Future<void> inviteByTouristId(TouristGroup group, String rawId) async {
    final uid = _requireUid();
    if (!group.isLeader(uid) || !group.isActive) {
      throw const TouristGroupException(
        'Only the group leader can invite people.',
      );
    }
    final found = await lookupRegisteredTourist(rawId);
    if (found == null) {
      throw const TouristGroupException(
        'No registered tourist account has that Tourist ID.',
      );
    }
    if (found.uid == uid) {
      throw const TouristGroupException('You are already the group leader.');
    }
    if (group.hasMember(found.uid) || group.hasPendingInvite(found.uid)) {
      throw const TouristGroupException(
        'That tourist is already in this group or has a pending invite.',
      );
    }
    final seats = group.memberCount + group.pendingInvites.length;
    if (seats >= TouristGroup.maxMembers) {
      throw const TouristGroupException(
        'This group is full (${TouristGroup.maxMembers} members).',
      );
    }
    await _col.doc(group.id).update({
      'pendingInviteUids': FieldValue.arrayUnion([found.uid]),
      'pendingInvites.${found.uid}': {
        ...found.member.toProfileMap(),
        'status': 'invited',
        if (found.member.touristId.isNotEmpty) 'touristId': found.member.touristId,
        'invitedAt': FieldValue.serverTimestamp(),
      },
    });
  }

  /// Accepts a pending invite and shares my registration snapshot.
  static Future<void> acceptInvite(TouristGroup group) async {
    final uid = _requireUid();
    if (!group.hasPendingInvite(uid)) {
      throw const TouristGroupException('This invitation is no longer active.');
    }
    if (!group.isActive) {
      throw const TouristGroupException(
        'This group has already ended. Ask your friend to create a new one.',
      );
    }
    await _exitCurrentGroups(uid);
    final me = await _selfSnapshot(uid);
    await _col.doc(group.id).update({
      'memberUids': FieldValue.arrayUnion([uid]),
      'members.$uid': me.toGroupMap(),
      'pendingInviteUids': FieldValue.arrayRemove([uid]),
      'pendingInvites.$uid': FieldValue.delete(),
    });
  }

  static Future<void> cancelInvite(TouristGroup group, String memberUid) async {
    final uid = _requireUid();
    if (!group.isLeader(uid)) return;
    await _col.doc(group.id).update({
      'pendingInviteUids': FieldValue.arrayRemove([memberUid]),
      'pendingInvites.$memberUid': FieldValue.delete(),
    });
  }

  static Future<void> declineInvite(TouristGroup group) async {
    final uid = _requireUid();
    await _col.doc(group.id).update({
      'pendingInviteUids': FieldValue.arrayRemove([uid]),
      'pendingInvites.$uid': FieldValue.delete(),
    });
  }

  static Stream<List<TouristGroup>> watchMyInvites() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return Stream.value(const []);
    return _col
        .where('pendingInviteUids', arrayContains: uid)
        .where('status', isEqualTo: 'active')
        .limit(5)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(TouristGroup.fromDoc)
              .where((g) => g.isActive && g.hasPendingInvite(uid))
              .toList(),
        );
  }

  /// Copies group check-in notices into this phone's notification list.
  static Future<void> deliverMyCheckInNotices() async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final groups = await _groupsWithMember(uid);
      final prefs = await SharedPreferences.getInstance();
      final key = 'laag_notice_seen_$uid';
      final seen = prefs.getStringList(key)?.toSet() ?? <String>{};
      var changed = false;
      for (final g in groups) {
        final doc = await _col.doc(g.id).get();
        final raw = doc.data()?['notices'];
        if (raw is! Map) continue;
        for (final entry in raw.entries) {
          final id = entry.key.toString();
          if (seen.contains(id)) continue;
          final value = entry.value;
          if (value is! Map) continue;
          final notice = Map<String, dynamic>.from(value);
          if (notice['uid']?.toString() != uid) continue;
          await UserActivityService.addNotificationIfAbsent(
            id: id,
            title: notice['title']?.toString() ?? 'Group check-in',
            message: notice['message']?.toString() ??
                'You were checked in with ${g.name}.',
            type: NotificationType.system,
          );
          seen.add(id);
          changed = true;
        }
      }
      if (changed) {
        final list = seen.toList();
        await prefs.setStringList(
          key,
          list.length > 80 ? list.sublist(list.length - 80) : list,
        );
      }
    } catch (e) {
      debugPrint('[TouristGroup] notice delivery skipped: $e');
    }
  }

  /// Joins [group] and shares my demographic snapshot with it.
  static Future<TouristGroup> join(TouristGroup group) async {
    final uid = _requireUid();
    if (!group.isActive) {
      throw const TouristGroupException(
        'This group has already ended. Ask your friend to create a new one.',
      );
    }
    if (group.hasMember(uid)) return group;
    if (group.memberCount >= TouristGroup.maxMembers) {
      throw const TouristGroupException(
        'This group is full (${TouristGroup.maxMembers} members).',
      );
    }
    await _exitCurrentGroups(uid);
    final me = await _selfSnapshot(uid);
    await _col.doc(group.id).update({
      'memberUids': FieldValue.arrayUnion([uid]),
      'members.$uid': me.toGroupMap(),
    });
    return TouristGroup.fromDoc(await _col.doc(group.id).get());
  }

  static Future<void> _leaveDoc(String groupId, String uid) {
    return _col.doc(groupId).update({
      'memberUids': FieldValue.arrayRemove([uid]),
      'members.$uid': FieldValue.delete(),
    });
  }

  /// Leaves [group]; when I am the leader the group ends for everyone.
  static Future<void> leave(TouristGroup group) async {
    final uid = _requireUid();
    if (group.isLeader(uid)) {
      await endGroup(group);
    } else {
      await _leaveDoc(group.id, uid);
    }
  }

  static Future<void> endGroup(TouristGroup group) async {
    _requireUid();
    await _col.doc(group.id).update({'status': 'ended'});
  }

  /// Leader removes another member.
  static Future<void> removeMember(TouristGroup group, String memberUid) async {
    final uid = _requireUid();
    if (!group.isLeader(uid) || memberUid == uid) return;
    await _leaveDoc(group.id, memberUid);
  }

  /// One active group at a time: end groups I lead, leave groups I joined.
  static Future<void> _exitCurrentGroups(String uid) async {
    List<TouristGroup> groups;
    try {
      groups = await _groupsWithMember(uid);
    } catch (e) {
      debugPrint('[TouristGroup] current groups lookup skipped: $e');
      return;
    }
    for (final g in groups) {
      try {
        if (g.isLeader(uid)) {
          await _col.doc(g.id).update({'status': 'ended'});
        } else {
          await _leaveDoc(g.id, uid);
        }
      } catch (e) {
        debugPrint('[TouristGroup] exit ${g.id} skipped: $e');
      }
    }
  }
}
