import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Add a visited spot
  static Future<void> addVisit({
    required String spotId,
    required String spotName,
    required String category,
    String? imageUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final visits = await getVisitedSpots();
    
    // Check if already visited today
    final today = DateTime.now();
    final alreadyVisitedToday = visits.any((v) =>
        v.spotId == spotId &&
        v.visitedAt.year == today.year &&
        v.visitedAt.month == today.month &&
        v.visitedAt.day == today.day);
    
    if (!alreadyVisitedToday) {
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
    }
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
    final placesVisited = await getUniquePlacesVisited();
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
