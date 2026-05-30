import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atmos_trs_system/config/auth_config.dart';

/// Service to manage user activity data like visits, saved spots, and stats.
class UserActivityService {
  UserActivityService._();

  static const String _keyVisitedSpots = 'user_visited_spots';
  static const String _keySavedSpots = 'user_saved_spots';
  static const String _keyBadges = 'user_badges';
  static const String _keyFirstVisitDate = 'user_first_visit_date';
  static const String _keyNotifications = 'user_notifications';
  static const String _keyRecentlyViewed = 'user_recently_viewed_spots';

  // ============ RECENTLY VIEWED (Home / spot previews) ============

  /// Spots the user opened (e.g. bottom sheet on Home). Most recent first; max 30.
  static Future<List<VisitRecord>> getRecentlyViewed() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_keyRecentlyViewed);
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
      _keyRecentlyViewed,
      json.encode(list.map((v) => v.toJson()).toList()),
    );
    _schedulePushActivityToCloud();
  }

  // ============ VISITED SPOTS ============

  /// Get list of visited spot IDs with timestamps
  static Future<List<VisitRecord>> getVisitedSpots() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_keyVisitedSpots);
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((e) => VisitRecord.fromJson(e)).toList()
        ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    } catch (_) {
      return [];
    }
  }

  /// Loads visit history from Firestore (qr_checkins, checkins, check_ins,
  /// tourist_activity) and merges with local cache. Enriches from tourist_spots.
  static Future<List<VisitRecord>> syncVisitedSpotsFromQrCheckins() async {
    final uid = AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || Firebase.apps.isEmpty) {
      return getVisitedSpots();
    }

    final local = await getVisitedSpots();
    final bySpot = <String, VisitRecord>{};
    for (final v in local) {
      if (v.spotId.isNotEmpty) {
        _mergeVisitIntoMap(bySpot, v);
      }
    }

    try {
      await _mergeVisitsFromTouristActivityDoc(uid, bySpot);
      await _mergeVisitsFromCollection(
        collection: 'qr_checkins',
        uid: uid,
        bySpot: bySpot,
        userFieldCandidates: const ['tourist_id', 'userId', 'user_id'],
      );
      await _mergeVisitsFromCollection(
        collection: 'checkins',
        uid: uid,
        bySpot: bySpot,
        userFieldCandidates: const ['user_id'],
        locationIdField: 'location_id',
      );
      // Legacy `check_ins` is staff-only in security rules; tourists use the collections above.

      await _enrichVisitsFromTouristSpots(bySpot);

      if (bySpot.isEmpty) {
        debugPrint(
          'UserActivityService.syncVisitedSpots: no visits for uid=$uid',
        );
        return local;
      }

      final merged = bySpot.values.toList()
        ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _keyVisitedSpots,
        json.encode(merged.map((v) => v.toJson()).toList()),
      );
      _schedulePushActivityToCloud();
      debugPrint(
        'UserActivityService.syncVisitedSpots: ${merged.length} spot(s) for uid=$uid',
      );
      return merged;
    } catch (e, st) {
      debugPrint('UserActivityService.syncVisitedSpotsFromQrCheckins: $e\n$st');
      return local.isNotEmpty ? local : bySpot.values.toList();
    }
  }

  static void _mergeVisitIntoMap(
    Map<String, VisitRecord> bySpot,
    VisitRecord visit,
  ) {
    if (visit.spotId.isEmpty) return;
    final existing = bySpot[visit.spotId];
    if (existing == null || visit.visitedAt.isAfter(existing.visitedAt)) {
      bySpot[visit.spotId] = visit;
    }
  }

  static Future<void> _mergeVisitsFromTouristActivityDoc(
    String uid,
    Map<String, VisitRecord> bySpot,
  ) async {
    try {
      final act = await FirebaseFirestore.instance
          .collection('tourist_activity')
          .doc(uid)
          .get();
      final raw = act.data()?['visits'];
      if (raw is! List) return;
      for (final e in raw) {
        if (e is! Map) continue;
        final m = e is Map<String, dynamic>
            ? e
            : Map<String, dynamic>.from(e);
        final v = VisitRecord.fromJson(m);
        _mergeVisitIntoMap(bySpot, v);
      }
    } catch (e) {
      debugPrint('UserActivityService tourist_activity: $e');
    }
  }

  static Future<void> _mergeVisitsFromCollection({
    required String collection,
    required String uid,
    required Map<String, VisitRecord> bySpot,
    required List<String> userFieldCandidates,
    String? locationIdField,
  }) async {
    QuerySnapshot<Map<String, dynamic>>? snap;
    for (final field in userFieldCandidates) {
      try {
        snap = await FirebaseFirestore.instance
            .collection(collection)
            .where(field, isEqualTo: uid)
            .limit(400)
            .get();
        if (snap.docs.isNotEmpty) break;
      } catch (e) {
        debugPrint(
          'UserActivityService $collection.$field: $e',
        );
        snap = null;
      }
    }
    if (snap == null || snap.docs.isEmpty) return;

    for (final doc in snap.docs) {
      final visit = _visitRecordFromCheckInData(
        doc.data(),
        fallbackSpotId: locationIdField != null
            ? doc.data()[locationIdField]?.toString()
            : null,
      );
      if (visit != null) {
        _mergeVisitIntoMap(bySpot, visit);
      }
    }
  }

  static VisitRecord? _visitRecordFromCheckInData(
    Map<String, dynamic> d, {
    String? fallbackSpotId,
  }) {
    final spotId = (d['spotId'] ??
            d['spot_id'] ??
            d['location_id'] ??
            fallbackSpotId ??
            '')
        .toString()
        .trim();
    if (spotId.isEmpty) return null;

    var spotName = (d['spot_name'] ?? d['spotName'] ?? d['name'] ?? '')
        .toString()
        .trim();
    if (spotName.isEmpty) {
      spotName = spotId.replaceAll('_', ' ').replaceAll('-', ' ');
    }

    var category = (d['spotCategory'] ??
            d['category'] ??
            d['municipality'] ??
            'Spot')
        .toString()
        .trim();
    if (category.isEmpty) category = 'Spot';

    final visitedAt = _parseCheckInTimestamp(
      d['timestamp'] ??
          d['checkin_time'] ??
          d['checkedInAt'] ??
          d['createdAt'],
    );

    final imageUrl = (d['image'] ?? d['imageUrl'] ?? d['spot_image'])
        ?.toString()
        .trim();

    return VisitRecord(
      spotId: spotId,
      spotName: spotName,
      category: category,
      imageUrl: imageUrl != null && imageUrl.isNotEmpty ? imageUrl : null,
      visitedAt: visitedAt,
    );
  }

  static DateTime _parseCheckInTimestamp(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        ts > 9999999999 ? ts : ts * 1000,
      );
    }
    final s = ts?.toString().trim() ?? '';
    if (s.isNotEmpty) {
      return DateTime.tryParse(s) ?? DateTime.now();
    }
    return DateTime.now();
  }

  /// Fills missing names/images from `tourist_spots` documents.
  static Future<void> _enrichVisitsFromTouristSpots(
    Map<String, VisitRecord> bySpot,
  ) async {
    if (bySpot.isEmpty || Firebase.apps.isEmpty) return;
    final ids = bySpot.keys.toList();
    const chunkSize = 10;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = math.min(i + chunkSize, ids.length);
      final chunk = ids.sublist(i, end);
      try {
        final docs = await Future.wait(
          chunk.map(
            (id) => FirebaseFirestore.instance
                .collection('tourist_spots')
                .doc(id)
                .get(),
          ),
        );
        for (final doc in docs) {
          if (!doc.exists) continue;
          final data = doc.data();
          if (data == null) continue;
          final existing = bySpot[doc.id];
          if (existing == null) continue;

          final name = data['name']?.toString().trim();
          final category = data['category']?.toString().trim();
          final image = (data['image'] ?? data['imageUrl'])?.toString().trim();

          bySpot[doc.id] = VisitRecord(
            spotId: doc.id,
            spotName: (name != null && name.isNotEmpty)
                ? name
                : existing.spotName,
            category: (category != null && category.isNotEmpty)
                ? category
                : existing.category,
            imageUrl: (image != null && image.isNotEmpty)
                ? image
                : existing.imageUrl,
            visitedAt: existing.visitedAt,
          );
        }
      } catch (e) {
        debugPrint('UserActivityService enrich tourist_spots: $e');
      }
    }
  }

  /// Add a visited spot
  static Future<void> addVisit({
    required String spotId,
    required String spotName,
    required String category,
    String? imageUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final visits = await getVisitedSpots();
    
    // Count each tourist spot only once in the visitor history.
    final alreadyVisitedSpot = visits.any((v) => v.spotId == spotId);

    if (!alreadyVisitedSpot) {
      visits.insert(0, VisitRecord(
        spotId: spotId,
        spotName: spotName,
        category: category,
        imageUrl: imageUrl,
        visitedAt: DateTime.now(),
      ));
      
      await prefs.setString(
        _keyVisitedSpots,
        json.encode(visits.map((v) => v.toJson()).toList()),
      );
      
      // Check for badge achievements
      await _checkBadgeAchievements(visits.length);
      _schedulePushActivityToCloud();
    }
  }

  /// Backs up visits + badges + recently viewed + saved spots so progress
  /// survives reinstall / new device.
  static Future<void> pushVisitAndBadgeSnapshotToCloud(String uid) async {
    if (uid.isEmpty) return;
    try {
      if (Firebase.apps.isEmpty) return;
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
      _keyVisitedSpots,
      json.encode(sorted.map((v) => v.toJson()).toList()),
    );
    await prefs.setString(
      _keyBadges,
      json.encode(badges.map((b) => b.toJson()).toList()),
    );
    final viewed = List<VisitRecord>.from(recentlyViewed)
      ..sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    await prefs.setString(
      _keyRecentlyViewed,
      json.encode(viewed.map((v) => v.toJson()).toList()),
    );
    await prefs.setStringList(_keySavedSpots, savedSpotIds.toSet().toList());
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
    return prefs.getStringList(_keySavedSpots) ?? [];
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
    
    await prefs.setStringList(_keySavedSpots, savedSpots);
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
    final jsonString = prefs.getString(_keyBadges);
    if (jsonString == null || jsonString.isEmpty) return [];
    
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((e) => Badge.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Add a badge
  static Future<void> _addBadge(Badge badge) async {
    final prefs = await SharedPreferences.getInstance();
    final badges = await getEarnedBadges();
    
    // Don't add duplicate badges
    if (badges.any((b) => b.id == badge.id)) return;
    
    badges.add(badge);
    await prefs.setString(
      _keyBadges,
      json.encode(badges.map((b) => b.toJson()).toList()),
    );
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
      await _addBadge(newBadge);
      await addNotification(
        title: 'New Badge Earned!',
        message: 'You earned the "${newBadge.name}" badge!',
        type: NotificationType.badge,
      );
    }
    
    return newBadge;
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
    final firstVisitString = prefs.getString(_keyFirstVisitDate);
    
    if (firstVisitString == null) {
      // Set first visit date to now
      await prefs.setString(_keyFirstVisitDate, DateTime.now().toIso8601String());
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
    final jsonString = prefs.getString(_keyNotifications);
    if (jsonString == null || jsonString.isEmpty) return [];
    
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((e) => AppNotification.fromJson(e)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
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
      _keyNotifications,
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
    ));
    final trimmed = notifications.take(50).toList();
    await prefs.setString(
      _keyNotifications,
      json.encode(trimmed.map((n) => n.toJson()).toList()),
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
        _keyNotifications,
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
      _keyNotifications,
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
    await prefs.remove(_keyNotifications);
  }

  // ============ USER STATS ============

  /// Get all user stats at once
  static Future<UserStats> getUserStats() async {
    final placesVisited = await getTotalVisitsCount();
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

  /// Clear all user activity data
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyVisitedSpots);
    await prefs.remove(_keySavedSpots);
    await prefs.remove(_keyBadges);
    await prefs.remove(_keyFirstVisitDate);
    await prefs.remove(_keyNotifications);
    await prefs.remove(_keyRecentlyViewed);
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

enum NotificationType { badge, event, weather, checkin, system }

class AppNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime createdAt;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    required this.isRead,
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
