import 'package:cloud_firestore/cloud_firestore.dart';

/// Demographic snapshot a member shares when joining a "Laag with Friends" group.
///
/// Written by the member's own device into `tourist_groups/{id}.members[uid]`
/// and copied onto the group check-in so DOT forms count each person.
class TouristGroupMember {
  const TouristGroupMember({
    required this.uid,
    required this.name,
    this.sex = '',
    this.nationality = '',
    this.country = '',
    this.province = '',
    this.city = '',
    this.isLocal,
    this.localOrForeign = '',
    this.joinedAt,
  });

  final String uid;
  final String name;
  final String sex;
  final String nationality;
  final String country;
  final String province;
  final String city;
  final bool? isLocal;
  final String localOrForeign;
  final DateTime? joinedAt;

  factory TouristGroupMember.fromMap(String uid, Map<String, dynamic> m) {
    final joined = m['joinedAt'];
    return TouristGroupMember(
      uid: (m['uid']?.toString().trim().isNotEmpty ?? false)
          ? m['uid'].toString().trim()
          : uid,
      name: m['name']?.toString().trim() ?? '',
      sex: m['sex']?.toString().trim() ?? '',
      nationality: m['nationality']?.toString().trim() ?? '',
      country: m['country']?.toString().trim() ?? '',
      province: m['province']?.toString().trim() ?? '',
      city: m['city']?.toString().trim() ?? '',
      isLocal: m['isLocal'] is bool ? m['isLocal'] as bool : null,
      localOrForeign: m['localOrForeign']?.toString().trim() ?? '',
      joinedAt: joined is Timestamp
          ? joined.toDate()
          : (joined is DateTime ? joined : null),
    );
  }

  /// Snapshot built from the member's own `tourists/{uid}` document.
  factory TouristGroupMember.fromTouristDoc(
    String uid,
    Map<String, dynamic> t, {
    String fallbackName = '',
  }) {
    final full = t['fullName']?.toString().trim() ?? '';
    final composed = full.isNotEmpty
        ? full
        : [
            t['firstName']?.toString().trim() ?? '',
            t['lastName']?.toString().trim() ?? '',
          ].where((s) => s.isNotEmpty).join(' ');
    return TouristGroupMember(
      uid: uid,
      name: composed.isNotEmpty ? composed : fallbackName,
      sex: t['sex']?.toString().trim() ?? '',
      nationality: t['nationality']?.toString().trim() ?? '',
      country: t['country']?.toString().trim() ?? '',
      province: t['province']?.toString().trim() ?? '',
      city: t['city']?.toString().trim() ?? '',
      isLocal: t['isLocal'] is bool ? t['isLocal'] as bool : null,
      localOrForeign: t['localOrForeign']?.toString().trim() ?? '',
    );
  }

  /// Profile-shaped map (same keys as `tourists/{uid}`) used by report aggregators.
  Map<String, dynamic> toProfileMap() => {
        'uid': uid,
        'name': name,
        'sex': sex,
        'nationality': nationality,
        'country': country,
        'province': province,
        'city': city,
        if (isLocal != null) 'isLocal': isLocal,
        'localOrForeign': localOrForeign,
      };

  /// Firestore map stored in the group document (adds `joinedAt`).
  Map<String, dynamic> toGroupMap({bool serverJoinedAt = true}) => {
        ...toProfileMap(),
        'joinedAt': serverJoinedAt
            ? FieldValue.serverTimestamp()
            : (joinedAt == null ? null : Timestamp.fromDate(joinedAt!)),
      };
}

/// A "Laag with Friends" travel group (barkada / family) for one trip day.
class TouristGroup {
  const TouristGroup({
    required this.id,
    required this.leaderUid,
    required this.name,
    required this.joinCode,
    required this.status,
    required this.memberUids,
    required this.members,
    this.createdAt,
    this.expiresAt,
  });

  static const String collection = 'tourist_groups';
  static const int maxMembers = 30;
  static const Duration lifetime = Duration(hours: 12);
  static const String qrPrefix = 'ATMOS-TRS-GROUP:';

  final String id;
  final String leaderUid;
  final String name;
  final String joinCode;
  final String status;
  final List<String> memberUids;
  final Map<String, TouristGroupMember> members;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  bool get isActive => status == 'active' && !isExpired;

  bool isLeader(String uid) => uid.isNotEmpty && leaderUid == uid;

  bool hasMember(String uid) => memberUids.contains(uid);

  int get memberCount => memberUids.length;

  /// Members in join order with the leader first.
  List<TouristGroupMember> get orderedMembers {
    final list = <TouristGroupMember>[
      for (final uid in memberUids)
        members[uid] ?? TouristGroupMember(uid: uid, name: ''),
    ];
    list.sort((a, b) {
      if (a.uid == leaderUid) return -1;
      if (b.uid == leaderUid) return 1;
      return 0;
    });
    return list;
  }

  String get qrPayload => buildQrPayload(id, joinCode);

  static String buildQrPayload(String groupId, String code) =>
      '$qrPrefix$groupId:$code';

  /// Parses `ATMOS-TRS-GROUP:<groupId>:<code>`; null when not a group QR.
  static ({String groupId, String code})? parseQrPayload(String raw) {
    final s = raw.trim();
    if (!s.toUpperCase().startsWith(qrPrefix)) return null;
    final rest = s.substring(qrPrefix.length);
    final parts = rest.split(':');
    if (parts.length < 2) return null;
    final id = parts[0].trim();
    final code = parts[1].trim().toUpperCase();
    if (id.isEmpty || code.isEmpty) return null;
    return (groupId: id, code: code);
  }

  factory TouristGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final uids = (d['memberUids'] is List)
        ? (d['memberUids'] as List)
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];
    final rawMembers = d['members'] is Map
        ? Map<String, dynamic>.from(d['members'] as Map)
        : const <String, dynamic>{};
    final members = <String, TouristGroupMember>{};
    rawMembers.forEach((uid, value) {
      if (value is Map) {
        members[uid] = TouristGroupMember.fromMap(
          uid,
          Map<String, dynamic>.from(value),
        );
      }
    });
    DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : null;
    return TouristGroup(
      id: doc.id,
      leaderUid: d['leaderUid']?.toString() ?? '',
      name: d['name']?.toString() ?? '',
      joinCode: d['joinCode']?.toString() ?? '',
      status: d['status']?.toString() ?? 'active',
      memberUids: uids,
      members: members,
      createdAt: ts(d['createdAt']),
      expiresAt: ts(d['expiresAt']),
    );
  }
}
