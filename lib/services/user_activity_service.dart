import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/utils/checkin_dedupe.dart';

/// Service to manage user activity data like visits, saved spots, and stats.
class UserActivityService {
  UserActivityService._();

  /// Notifies Home / Visited UI after a QR check-in is recorded locally.
  static final ValueNotifier<int> visitedSpotsRevision = ValueNotifier<int>(0);

  static void _notifyVisitedChanged() {
    visitedSpotsRevision.value = visitedSpotsRevision.value + 1;
  }

  static const String _keyVisitedSpots = 'user_visited_spots';
  static const String _keySavedSpots = 'user_saved_spots';
  static const String _keyBadges = 'user_badges';
  static const String _keyFirstVisitDate = 'user_first_visit_date';
  static const String _keyNotifications = 'user_notifications';
  static const String _keyRecentlyViewed = 'user_recently_viewed_spots';
  static const String _keyActivityBoundUid = 'user_activity_bound_uid';

  static String? _boundUidCache;

  /// Binds local activity storage to [uid] so a new account on the same device
  /// does not inherit another user's visits or notifications.
  static Future<void> bindToUser(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(_keyActivityBoundUid);
    _boundUidCache = id;
    await prefs.setString(_keyActivityBoundUid, id);
    await _migrateUnscopedKeysIfNeeded(prefs, id);
    if (previous != null && previous.isNotEmpty && previous != id) {
      _boundUidCache = id;
    }
  }

  /// Older builds wrote visits to unscoped keys; copy into uid-scoped keys once.
  static Future<void> _migrateUnscopedKeysIfNeeded(
    SharedPreferences prefs,
    String uid,
  ) async {
    Future<void> migrateString(String base) async {
      final scoped = '${base}_$uid';
      final scopedVal = prefs.getString(scoped);
      if (scopedVal != null && scopedVal.isNotEmpty) return;
      final legacy = prefs.getString(base);
      if (legacy != null && legacy.isNotEmpty) {
        await prefs.setString(scoped, legacy);
      }
    }

    Future<void> migrateStringList(String base) async {
      final scoped = '${base}_$uid';
      final scopedVal = prefs.getStringList(scoped);
      if (scopedVal != null && scopedVal.isNotEmpty) return;
      final legacy = prefs.getStringList(base);
      if (legacy != null && legacy.isNotEmpty) {
        await prefs.setStringList(scoped, legacy);
      }
    }

    await migrateString(_keyVisitedSpots);
    await migrateString(_keyBadges);
    await migrateString(_keyRecentlyViewed);
    await migrateString(_keyNotifications);
    await migrateString(_keyFirstVisitDate);
    await migrateStringList(_keySavedSpots);
  }

  static Future<String?> _activeUid() async {
    if (_boundUidCache != null && _boundUidCache!.isNotEmpty) {
      return _boundUidCache;
    }
    final fromAuth =
        AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (fromAuth != null && fromAuth.isNotEmpty) {
      _boundUidCache = fromAuth;
      return fromAuth;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyActivityBoundUid);
    if (stored != null && stored.isNotEmpty) {
      _boundUidCache = stored;
      return stored;
    }
    return null;
  }

  static Future<String> _scoped(String base) async {
    final uid = await _activeUid();
    if (uid == null || uid.isEmpty) return base;
    return '${base}_$uid';
  }

  // ============ RECENTLY VIEWED (Home / spot previews) ============

  /// Spots the user opened (e.g. bottom sheet on Home). Most recent first; max 30.
  static Future<List<VisitRecord>> getRecentlyViewed() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(await _scoped(_keyRecentlyViewed));
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((e) => VisitRecord.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Call when the user opens a spot detail / preview (not necessarily check-in).
  static Future<void> recordRecentlyViewed({
    required String spotId,
    required String spotName,
    required String category,
    String? imageUrl,
  }) async {
    if (spotId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    var list = await getRecentlyViewed();
    list.removeWhere((v) => v.spotId == spotId);
    list.insert(
      0,
      VisitRecord(
        spotId: spotId,
        spotName: spotName,
        category: category,
        imageUrl: imageUrl,
        visitedAt: DateTime.now(),
      ),
    );
    if (list.length > 30) {
      list = list.sublist(0, 30);
    }
    await prefs.setString(
      await _scoped(_keyRecentlyViewed),
      json.encode(list.map((v) => v.toJson()).toList()),
    );
    _schedulePushActivityToCloud();
  }

  // ============ VISITED SPOTS ============

  /// Replaces the full visited list in local storage (e.g. after enriching images).
  static Future<void> replaceVisitedSpots(List<VisitRecord> visits) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = List<VisitRecord>.from(visits)
      ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    await prefs.setString(
      await _scoped(_keyVisitedSpots),
      json.encode(sorted.map((v) => v.toJson()).toList()),
    );
    _notifyVisitedChanged();
  }

  /// Get list of visited spot IDs with timestamps
  static Future<List<VisitRecord>> getVisitedSpots() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(await _scoped(_keyVisitedSpots));
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((e) => VisitRecord.fromJson(e)).toList()
        ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    } catch (_) {
      return [];
    }
  }

  static void _mergeCheckInRowIntoBySpot(
    Map<String, VisitRecord> bySpot,
    Map<String, dynamic> d,
  ) {
    final spotId = CheckInDedupe.spotId(d);
    if (spotId.isEmpty) return;

    var spotName = (d['spot_name'] ?? d['spotName'] ?? d['location'] ?? '')
        .toString()
        .trim();
    if (spotName.isEmpty) {
      if (_isLguOnlyCheckIn(spotId)) {
        final muni = (d['municipality'] ?? '').toString().trim();
        spotName = muni.isNotEmpty ? 'LGU visit — $muni' : 'LGU visit';
      } else {
        spotName = spotId.replaceAll('_', ' ');
      }
    }
    var category = (d['category'] ?? d['spotCategory'] ?? '').toString().trim();
    if (category.isEmpty) {
      category = (d['municipality'] ?? '').toString().trim();
    }
    if (category.isEmpty) {
      category = _isLguOnlyCheckIn(spotId) ? 'LGU' : 'Spot';
    }

    var visitedAt = DateTime.now();
    final ts = d['timestamp'] ?? d['checkin_time'] ?? d['checkedInAt'] ?? d['createdAt'];
    if (ts is Timestamp) {
      visitedAt = ts.toDate();
    } else if (ts is String) {
      visitedAt = DateTime.tryParse(ts) ?? visitedAt;
    }

    final imageRaw = (d['imageUrl'] ?? d['image_url'] ?? '').toString().trim();
    final imageUrl = imageRaw.isNotEmpty ? imageRaw : null;

    final existing = bySpot[spotId];
    if (existing == null || visitedAt.isAfter(existing.visitedAt)) {
      bySpot[spotId] = VisitRecord(
        spotId: spotId,
        spotName: spotName,
        category: category,
        imageUrl: imageUrl ?? existing?.imageUrl,
        visitedAt: visitedAt,
      );
    }
  }

  /// Municipality LGU QR check-ins use spot ids like `lgu_oroquieta`.
  static bool _isLguOnlyCheckIn(String spotId) {
    return spotId.trim().toLowerCase().startsWith('lgu_');
  }

  /// Loads the user's docs from [collection], trying every uid field variant.
  /// An empty first query must not skip the others (Firestore returns [] not throw).
  ///
  /// With [includeGroupVisits], also loads "Laag with Friends" check-ins where
  /// a group leader checked this user in (`groupMemberUids` array-contains).
  static Future<List<Map<String, dynamic>>> _queryUserRows(
    String collection,
    String uid, {
    bool includeGroupVisits = false,
  }) async {
    final db = FirebaseFirestore.instance;
    final byDocId = <String, Map<String, dynamic>>{};
    Future<QuerySnapshot<Map<String, dynamic>>?> safe(
      Query<Map<String, dynamic>> q,
      String label,
    ) {
      return q
          .limit(300)
          .get()
          .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s)
          .catchError((Object e) {
        debugPrint('[UserActivity] $collection $label skipped: $e');
        return null;
      });
    }

    final snaps = await Future.wait([
      for (final field in ['userId', 'tourist_id', 'user_id'])
        safe(
          db.collection(collection).where(field, isEqualTo: uid),
          'where $field',
        ),
      if (includeGroupVisits)
        safe(
          db
              .collection(collection)
              .where('groupMemberUids', arrayContains: uid),
          'group visits',
        ),
    ]);
    for (final snap in snaps) {
      if (snap == null) continue;
      for (final doc in snap.docs) {
        byDocId[doc.id] = doc.data();
      }
    }
    return byDocId.values.toList();
  }

  /// Rebuilds local visit history from Firestore QR check-ins + local visits.
  static Future<List<VisitRecord>> syncVisitedSpotsFromQrCheckins() async {
    final uid = AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || Firebase.apps.isEmpty) {
      return getVisitedSpots();
    }

    final local = await getVisitedSpots();
    try {
      final bySpot = <String, VisitRecord>{};
      var firestoreQueried = false;
      final qrFuture =
          _queryUserRows('qr_checkins', uid, includeGroupVisits: true);
      final checkinsFuture = _queryUserRows('checkins', uid);

      try {
        final qrRows = await qrFuture;
        firestoreQueried = true;
        for (final row in CheckInDedupe.oneVisitPerUserSpotDay(qrRows)) {
          _mergeCheckInRowIntoBySpot(bySpot, row);
        }
      } catch (e) {
        debugPrint('[UserActivity] qr_checkins sync skipped: $e');
      }

      try {
        final checkinRows = await checkinsFuture;
        firestoreQueried = true;
        for (final row in checkinRows) {
          final spotId = CheckInDedupe.spotId(row);
          if (spotId.isEmpty || bySpot.containsKey(spotId)) continue;
          _mergeCheckInRowIntoBySpot(bySpot, row);
        }
      } catch (e) {
        debugPrint('[UserActivity] checkins sync skipped: $e');
      }

      // Always keep local visits (spot + LGU) so a just-saved check-in is never dropped.
      for (final v in local) {
        if (v.spotId.isEmpty) continue;
        final existing = bySpot[v.spotId];
        if (existing == null || v.visitedAt.isAfter(existing.visitedAt)) {
          bySpot[v.spotId] = v;
        } else if ((existing.spotName.trim().isEmpty ||
                existing.spotName == existing.spotId) &&
            v.spotName.trim().isNotEmpty) {
          bySpot[v.spotId] = existing.copyWith(
            spotName: v.spotName,
            category: v.category.trim().isNotEmpty ? v.category : existing.category,
            imageUrl: v.imageUrl ?? existing.imageUrl,
          );
        }
      }

      if (!firestoreQueried && bySpot.isEmpty) return local;

      final merged = bySpot.values.toList()
        ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        await _scoped(_keyVisitedSpots),
        json.encode(merged.map((v) => v.toJson()).toList()),
      );
      _schedulePushActivityToCloud();
      _notifyVisitedChanged();
      return merged;
    } catch (e) {
      debugPrint('UserActivityService.syncVisitedSpotsFromQrCheckins: $e');
      return local;
    }
  }

  /// Add a visited spot
  static Future<void> addVisit({
    required String spotId,
    required String spotName,
    required String category,
    String? imageUrl,
  }) async {
    final id = spotId.trim();
    if (id.isEmpty) return;
    final name = spotName.trim().isNotEmpty ? spotName.trim() : id.replaceAll('_', ' ');
    final cat = category.trim().isNotEmpty ? category.trim() : 'Spot';

    final uid =
        AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await bindToUser(uid);
    }

    final prefs = await SharedPreferences.getInstance();
    final visits = await getVisitedSpots();
    
    final img = imageUrl?.trim();
    final existingIndex = visits.indexWhere((v) => v.spotId == id);

    if (existingIndex >= 0) {
      final existing = visits[existingIndex];
      final updated = existing.copyWith(
        spotName: name,
        category: cat,
        visitedAt: DateTime.now(),
        imageUrl: (img != null && img.isNotEmpty)
            ? img
            : existing.imageUrl,
      );
      visits.removeAt(existingIndex);
      visits.insert(0, updated);
      await prefs.setString(
        await _scoped(_keyVisitedSpots),
        json.encode(visits.map((v) => v.toJson()).toList()),
      );
      _schedulePushActivityToCloud();
      _notifyVisitedChanged();
      return;
    }

    visits.insert(0, VisitRecord(
      spotId: id,
      spotName: name,
      category: cat,
      imageUrl: imageUrl,
      visitedAt: DateTime.now(),
    ));

    await prefs.setString(
      await _scoped(_keyVisitedSpots),
      json.encode(visits.map((v) => v.toJson()).toList()),
    );

    // Check for badge achievements
    await _checkBadgeAchievements(
      visits.map((v) => v.spotId).where((sid) => sid.isNotEmpty).toSet().length,
    );
    _schedulePushActivityToCloud();
    _notifyVisitedChanged();
  }

  /// Backs up visits + badges + recently viewed + saved spots so progress
  /// survives reinstall / new device.
  static Future<void> pushVisitAndBadgeSnapshotToCloud(String uid) async {
    if (uid.isEmpty) return;
    try {
      if (Firebase.apps.isEmpty) return;
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null || authUser.uid != uid) return;
      final visits = await getVisitedSpots();
      final badges = await getEarnedBadges();
      final recentlyViewed = await getRecentlyViewed();
      final savedSpots = await getSavedSpotIds();
      await FirebaseFirestore.instance.collection('tourist_activity').doc(uid).set(
        {
          'visits': visits.map((v) => v.toJson()).toList(),
          'badges': badges.map((b) => b.toJson()).toList(),
          'recentlyViewed': recentlyViewed.map((v) => v.toJson()).toList(),
          'savedSpots': savedSpots,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('UserActivityService.pushVisitAndBadgeSnapshotToCloud: $e');
    }
  }

  static void _schedulePushActivityToCloud() {
    final uid = AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    pushVisitAndBadgeSnapshotToCloud(uid);
  }

  /// After merging local + server lists (login / app start).
  static Future<void> applyMergedActivityFromCloud({
    required List<VisitRecord> visits,
    required List<Badge> badges,
    required List<VisitRecord> recentlyViewed,
    required List<String> savedSpotIds,
    required String uid,
  }) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final sorted = List<VisitRecord>.from(visits)
      ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    await prefs.setString(
      await _scoped(_keyVisitedSpots),
      json.encode(sorted.map((v) => v.toJson()).toList()),
    );
    await prefs.setString(
      await _scoped(_keyBadges),
      json.encode(badges.map((b) => b.toJson()).toList()),
    );
    final viewed = List<VisitRecord>.from(recentlyViewed)
      ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    await prefs.setString(
      await _scoped(_keyRecentlyViewed),
      json.encode(viewed.map((v) => v.toJson()).toList()),
    );
    await prefs.setStringList(
      await _scoped(_keySavedSpots),
      savedSpotIds.toSet().toList(),
    );
    for (final t in [1, 5, 10, 25]) {
      if (sorted.length >= t) {
        await _checkBadgeAchievements(t);
      }
    }
    await pushVisitAndBadgeSnapshotToCloud(uid);
  }

  /// Get unique places visited count
  static Future<int> getUniquePlacesVisited() async {
    final visits = await getVisitedSpots();
    return visits.map((v) => v.spotId).toSet().length;
  }

  // ============ SAVED SPOTS ============

  /// Get list of saved spot IDs
  static Future<List<String>> getSavedSpotIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(await _scoped(_keySavedSpots)) ?? [];
  }

  /// Check if a spot is saved
  static Future<bool> isSpotSaved(String spotId) async {
    final savedSpots = await getSavedSpotIds();
    return savedSpots.contains(spotId);
  }

  /// Toggle save/unsave a spot
  static Future<bool> toggleSaveSpot(String spotId) async {
    final prefs = await SharedPreferences.getInstance();
    final savedSpots = await getSavedSpotIds();
    
    bool isSaved;
    if (savedSpots.contains(spotId)) {
      savedSpots.remove(spotId);
      isSaved = false;
    } else {
      savedSpots.add(spotId);
      isSaved = true;
    }
    
    await prefs.setStringList(await _scoped(_keySavedSpots), savedSpots);
    _schedulePushActivityToCloud();
    return isSaved;
  }

  /// Get saved spots count
  static Future<int> getSavedSpotsCount() async {
    final savedSpots = await getSavedSpotIds();
    return savedSpots.length;
  }

  // ============ BADGES ============

  /// Get earned badges
  static Future<List<Badge>> getEarnedBadges() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(await _scoped(_keyBadges));
    if (jsonString == null || jsonString.isEmpty) return [];
    
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((e) => Badge.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Add a badge. Returns true when the badge was newly earned.
  static Future<bool> _addBadge(Badge badge) async {
    final prefs = await SharedPreferences.getInstance();
    final badges = await getEarnedBadges();
    
    // Don't add duplicate badges
    if (badges.any((b) => b.id == badge.id)) return false;
    
    badges.add(badge);
    await prefs.setString(
      await _scoped(_keyBadges),
      json.encode(badges.map((b) => b.toJson()).toList()),
    );
    return true;
  }

  /// Check and award badges based on achievements
  static Future<Badge?> _checkBadgeAchievements(int totalVisits) async {
    Badge? newBadge;
    
    if (totalVisits == 1) {
      newBadge = Badge(
        id: 'first_visit',
        name: 'First Steps',
        description: 'Made your first check-in!',
        icon: 'explore',
        earnedAt: DateTime.now(),
      );
    } else if (totalVisits == 5) {
      newBadge = Badge(
        id: 'explorer',
        name: 'Explorer',
        description: 'Visited 5 tourist spots!',
        icon: 'emoji_events',
        earnedAt: DateTime.now(),
      );
    } else if (totalVisits == 10) {
      newBadge = Badge(
        id: 'adventurer',
        name: 'Adventurer',
        description: 'Visited 10 tourist spots!',
        icon: 'military_tech',
        earnedAt: DateTime.now(),
      );
    } else if (totalVisits == 25) {
      newBadge = Badge(
        id: 'travel_guru',
        name: 'Travel Guru',
        description: 'Visited 25 tourist spots!',
        icon: 'workspace_premium',
        earnedAt: DateTime.now(),
      );
    }
    
    if (newBadge != null) {
      final added = await _addBadge(newBadge);
      if (added) {
        await addNotificationIfAbsent(
          id: 'badge_${newBadge.id}',
          title: 'New Badge Earned!',
          message: 'You earned the "${newBadge.name}" badge!',
          type: NotificationType.badge,
        );
        return newBadge;
      }
      return null;
    }
    
    return null;
  }

  /// Get badges count
  static Future<int> getBadgesCount() async {
    final badges = await getEarnedBadges();
    return badges.length;
  }

  // ============ DAYS AS TOURIST ============

  /// Get days since first visit
  static Future<int> getDaysAsTourist() async {
    final prefs = await SharedPreferences.getInstance();
    final firstVisitKey = await _scoped(_keyFirstVisitDate);
    final firstVisitString = prefs.getString(firstVisitKey);
    
    if (firstVisitString == null) {
      // Set first visit date to now
      await prefs.setString(firstVisitKey, DateTime.now().toIso8601String());
      return 1;
    }
    
    try {
      final firstVisit = DateTime.parse(firstVisitString);
      final daysDiff = DateTime.now().difference(firstVisit).inDays;
      return daysDiff < 1 ? 1 : daysDiff + 1;
    } catch (_) {
      return 1;
    }
  }

  // ============ NOTIFICATIONS ============

  /// Get notifications
  static Future<List<AppNotification>> getNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _scoped(_keyNotifications);
    final jsonString = prefs.getString(key);
    if (jsonString == null || jsonString.isEmpty) return [];
    
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      final list = jsonList.map((e) => AppNotification.fromJson(e)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final pruned = _pruneDuplicateBadgeNotifications(list);
      if (pruned.length != list.length) {
        await prefs.setString(
          key,
          json.encode(pruned.map((n) => n.toJson()).toList()),
        );
      }
      return pruned;
    } catch (_) {
      return [];
    }
  }

  /// Collapse legacy duplicate "New Badge Earned!" rows (timestamp ids).
  static List<AppNotification> _pruneDuplicateBadgeNotifications(
    List<AppNotification> list,
  ) {
    final seenBadgeKeys = <String>{};
    final out = <AppNotification>[];
    for (final n in list) {
      if (n.type == NotificationType.badge) {
        final key = n.id.startsWith('badge_')
            ? n.id
            : 'msg:${n.message}';
        if (seenBadgeKeys.contains(key)) continue;
        seenBadgeKeys.add(key);
      }
      out.add(n);
    }
    return out;
  }

  /// Add a notification only if [id] is not already stored.
  static Future<void> addNotificationIfAbsent({
    required String id,
    required String title,
    required String message,
    required NotificationType type,
  }) async {
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final notifications = await getNotifications();
    if (notifications.any((n) => n.id == id)) return;

    notifications.insert(0, AppNotification(
      id: id,
      title: title,
      message: message,
      type: type,
      createdAt: DateTime.now(),
      isRead: false,
    ));

    final trimmed = notifications.take(50).toList();
    await prefs.setString(
      await _scoped(_keyNotifications),
      json.encode(trimmed.map((n) => n.toJson()).toList()),
    );
  }

  /// Add a notification
  static Future<void> addNotification({
    required String title,
    required String message,
    required NotificationType type,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final notifications = await getNotifications();
    
    notifications.insert(0, AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      message: message,
      type: type,
      createdAt: DateTime.now(),
      isRead: false,
    ));
    
    // Keep only last 50 notifications
    final trimmed = notifications.take(50).toList();
    
    await prefs.setString(
      await _scoped(_keyNotifications),
      json.encode(trimmed.map((n) => n.toJson()).toList()),
    );
  }

  /// Add a notification from a governor/tourism announcement (Firestore).
  /// Uses a stable id so the same announcement is not added twice.
  static Future<void> addNotificationFromAnnouncement({
    required String announcementId,
    required String title,
    required String message,
    NotificationType type = NotificationType.system,
    String? imageUrl,
    String? municipalityName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final notifications = await getNotifications();
    final stableId = 'ann_$announcementId';
    if (notifications.any((n) => n.id == stableId)) return;
    notifications.insert(0, AppNotification(
      id: stableId,
      title: title,
      message: message,
      type: type,
      createdAt: DateTime.now(),
      isRead: false,
      imageUrl: imageUrl,
      municipalityName: municipalityName,
    ));
    final trimmed = notifications.take(50).toList();
    await prefs.setString(
      await _scoped(_keyNotifications),
      json.encode(trimmed.map((n) => n.toJson()).toList()),
    );
  }

  /// Removes a stored notification by id.
  static Future<void> deleteNotification(String notificationId) async {
    if (notificationId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final notifications = await getNotifications();
    final next = notifications.where((n) => n.id != notificationId).toList();
    if (next.length == notifications.length) return;
    await prefs.setString(
      await _scoped(_keyNotifications),
      json.encode(next.map((n) => n.toJson()).toList()),
    );
  }

  /// Mark notification as read
  static Future<void> markNotificationAsRead(String notificationId) async {
    final prefs = await SharedPreferences.getInstance();
    final notifications = await getNotifications();
    
    final index = notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      notifications[index] = notifications[index].copyWith(isRead: true);
      await prefs.setString(
        await _scoped(_keyNotifications),
        json.encode(notifications.map((n) => n.toJson()).toList()),
      );
    }
  }

  /// Marks every stored notification (e.g. announcements mirrored on Home) as read.
  static Future<void> markAllNotificationsAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final notifications = await getNotifications();
    if (notifications.isEmpty) return;
    final updated = notifications.map((n) => n.copyWith(isRead: true)).toList();
    await prefs.setString(
      await _scoped(_keyNotifications),
      json.encode(updated.map((n) => n.toJson()).toList()),
    );
  }

  /// Get unread notifications count
  static Future<int> getUnreadNotificationsCount() async {
    final notifications = await getNotifications();
    return notifications.where((n) => !n.isRead).length;
  }

  /// Clear all notifications
  static Future<void> clearNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _scoped(_keyNotifications));
  }

  // ============ USER STATS ============

  /// Fast stats from local storage only (no Firestore network calls).
  static Future<UserStats> getUserStatsCached() async {
    final visits = await getVisitedSpots();
    final placesVisited = visits
        .map((v) => v.spotId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
    final badgesEarned = await getBadgesCount();
    final daysAsTourist = await getDaysAsTourist();
    final savedSpots = await getSavedSpotsCount();

    return UserStats(
      placesVisited: placesVisited,
      badgesEarned: badgesEarned,
      daysAsTourist: daysAsTourist,
      savedSpots: savedSpots,
    );
  }

  /// Get all user stats at once (syncs check-ins from Firestore first).
  static Future<UserStats> getUserStats() async {
    await syncVisitedSpotsFromQrCheckins();
    return getUserStatsCached();
  }

  /// Durable total visits count (Firestore + local fallback).
  /// Keeps user visit progress even when local cache changes.
  static Future<int> getTotalVisitsCount() async {
    final localCount = (await getVisitedSpots()).length;
    final uid = AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || Firebase.apps.isEmpty) return localCount;
    try {
      final doc = await FirebaseFirestore.instance.collection('tourists').doc(uid).get();
      final data = doc.data();
      final remoteRaw = data?['totalVisits'];
      final remoteCount = remoteRaw is num ? remoteRaw.toInt() : 0;
      return math.max(localCount, remoteCount);
    } catch (_) {
      return localCount;
    }
  }

  /// Clear all user activity data for the active account.
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _scoped(_keyVisitedSpots));
    await prefs.remove(await _scoped(_keySavedSpots));
    await prefs.remove(await _scoped(_keyBadges));
    await prefs.remove(await _scoped(_keyFirstVisitDate));
    await prefs.remove(await _scoped(_keyNotifications));
    await prefs.remove(await _scoped(_keyRecentlyViewed));
  }
}

// ============ DATA MODELS ============

class VisitRecord {
  final String spotId;
  final String spotName;
  final String category;
  final String? imageUrl;
  final DateTime visitedAt;

  VisitRecord({
    required this.spotId,
    required this.spotName,
    required this.category,
    this.imageUrl,
    required this.visitedAt,
  });

  VisitRecord copyWith({
    String? spotId,
    String? spotName,
    String? category,
    String? imageUrl,
    DateTime? visitedAt,
  }) {
    return VisitRecord(
      spotId: spotId ?? this.spotId,
      spotName: spotName ?? this.spotName,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      visitedAt: visitedAt ?? this.visitedAt,
    );
  }

  factory VisitRecord.fromJson(Map<String, dynamic> json) {
    return VisitRecord(
      spotId: json['spotId'] ?? '',
      spotName: json['spotName'] ?? '',
      category: json['category'] ?? '',
      imageUrl: json['imageUrl'],
      visitedAt: DateTime.tryParse(json['visitedAt'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'spotId': spotId,
      'spotName': spotName,
      'category': category,
      'imageUrl': imageUrl,
      'visitedAt': visitedAt.toIso8601String(),
    };
  }
}

class Badge {
  final String id;
  final String name;
  final String description;
  final String icon;
  final DateTime earnedAt;

  Badge({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.earnedAt,
  });

  factory Badge.fromJson(Map<String, dynamic> json) {
    return Badge(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      icon: json['icon'] ?? 'star',
      earnedAt: DateTime.tryParse(json['earnedAt'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'earnedAt': earnedAt.toIso8601String(),
    };
  }
}

enum NotificationType { badge, event, weather, checkin, system, welcome }

class AppNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime createdAt;
  final bool isRead;
  final String? imageUrl;
  final String? municipalityName;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    required this.isRead,
    this.imageUrl,
    this.municipalityName,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      type: NotificationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => NotificationType.system,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      isRead: json['isRead'] ?? false,
      imageUrl: json['imageUrl'] as String?,
      municipalityName: json['municipalityName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'type': type.name,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
      if (municipalityName != null && municipalityName!.isNotEmpty)
        'municipalityName': municipalityName,
    };
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      title: title,
      message: message,
      type: type,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      imageUrl: imageUrl,
      municipalityName: municipalityName,
    );
  }
}

class UserStats {
  final int placesVisited;
  final int badgesEarned;
  final int daysAsTourist;
  final int savedSpots;

  UserStats({
    required this.placesVisited,
    required this.badgesEarned,
    required this.daysAsTourist,
    required this.savedSpots,
  });
}
