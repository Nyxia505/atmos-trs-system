import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/models/notification_item.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart' as activity;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps tourist Home / notification bell in sync with published admin announcements.
class AnnouncementNotificationSync {
  AnnouncementNotificationSync._();

  /// Copies published `announcements` from Firestore into local activity storage
  /// only for posts published after the user registered.
  static Future<void> syncPublishedAnnouncementsToLocal({
    String? userId,
  }) async {
    try {
      final uid = await resolveUserId(userId);
      final cutoff = await registrationCutoffForUser(uid);
      if (uid != null && uid.isNotEmpty && cutoff == null) return;
      final announcements =
          await NotificationFirestoreService.getAnnouncements();
      for (final item in announcements) {
        if (cutoff != null && item.createdAt.isBefore(cutoff)) continue;
        await activity.UserActivityService.addNotificationFromAnnouncement(
          announcementId: item.id,
          title: item.title,
          message: item.message,
          type: _announcementTypeToActivity(item.type),
          imageUrl: item.imageUrl,
          municipalityName: item.municipalityName,
        );
      }
    } catch (e) {
      debugPrint('[AnnouncementNotificationSync] sync local: $e');
    }
  }

  /// Only announcements at or after this time should appear for [userId].
  static Future<DateTime?> registrationCutoffForUser(String? userId) async {
    return _registrationCutoff(userId);
  }

  static Future<DateTime?> _effectiveAnnouncementCutoff(String? userId) async {
    final uid = await resolveUserId(userId);
    if (uid == null || uid.isEmpty) return null;
    final registered = await registrationCutoffForUser(uid);
    return registered ?? DateTime.now();
  }

  static List<NotificationItem> _filterAnnouncementsForUser(
    List<NotificationItem> items,
    DateTime? cutoff,
    String? uid,
  ) {
    if (uid == null || uid.isEmpty) {
      return items.where((i) => !i.isAnnouncement).toList();
    }
    if (cutoff == null) {
      return items.where((i) => !i.isAnnouncement).toList();
    }
    return items.where((item) {
      if (!item.isAnnouncement) return true;
      return !item.createdAt.isBefore(cutoff);
    }).toList();
  }

  static Future<DateTime?> _registrationCutoff(String? userId) async {
    final uid = await resolveUserId(userId);
    if (uid == null || uid.isEmpty) return null;
    try {
      final db = FirebaseFirestore.instance;
      final userDoc = await db.collection('users').doc(uid).get();
      final userCreated = userDoc.data()?['createdAt'];
      if (userCreated is Timestamp) return userCreated.toDate();
      final touristDoc = await db.collection('tourists').doc(uid).get();
      final registeredAt = touristDoc.data()?['registeredAt'];
      if (registeredAt is Timestamp) return registeredAt.toDate();
    } catch (e) {
      debugPrint('[AnnouncementNotificationSync] registration cutoff: $e');
    }
    return null;
  }

  static Future<String?> resolveUserId([String? userId]) async {
    if (userId != null && userId.isNotEmpty) return userId;
    final fromAuth = AuthConfig.currentUserUid ??
        FirebaseAuth.instance.currentUser?.uid;
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;
    return SessionStorage.getStoredUser();
  }

  static Future<Set<String>> _loadDismissedAnnouncementIds(String uid) async {
    if (uid.isEmpty) return {};
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notif_dismissed_ann_$uid');
    if (list == null || list.isEmpty) return {};
    return list.toSet();
  }

  /// Applies local read + dismissed state (same rules as Alerts tab).
  static Future<List<NotificationItem>> loadAlertItems({String? userId}) async {
    final uid = await resolveUserId(userId);
    final cutoff = await _effectiveAnnouncementCutoff(uid);
    await syncPublishedAnnouncementsToLocal(userId: uid);
    final merged =
        await NotificationFirestoreService.getMergedNotifications(uid);
    await _mergeLocalUserNotificationsAsync(merged);
    final filtered = _filterAnnouncementsForUser(merged, cutoff, uid);
    return _applyLocalReadStateAndDismissed(filtered, uid);
  }

  static Future<void> _mergeLocalUserNotificationsAsync(
    List<NotificationItem> merged,
  ) async {
    final local = await activity.UserActivityService.getNotifications();
    final announcementKeys = <String>{
      for (final m in merged)
        if (m.isAnnouncement)
          '${m.title.trim().toLowerCase()}|${m.message.trim().toLowerCase()}',
    };
    for (final n in local) {
      if (n.id.startsWith('ann_')) continue;
      final type = _localTypeToNotificationString(n.type);
      final key =
          '${n.title.trim().toLowerCase()}|${n.message.trim().toLowerCase()}';
      if (announcementKeys.contains(key)) continue;
      final exists = merged.any(
        (m) =>
            m.id == n.id ||
            (type == 'welcome' && !m.isAnnouncement && m.type == 'welcome'),
      );
      if (exists) continue;
      merged.add(
        NotificationItem(
          id: n.id,
          title: n.title,
          message: n.message,
          type: type,
          createdAt: n.createdAt,
          isRead: n.isRead,
          isAnnouncement: false,
        ),
      );
    }
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static String _localTypeToNotificationString(
    activity.NotificationType type,
  ) {
    return switch (type) {
      activity.NotificationType.checkin => 'checkin',
      activity.NotificationType.badge => 'badge',
      activity.NotificationType.event => 'event',
      activity.NotificationType.weather => 'weather',
      activity.NotificationType.welcome => 'welcome',
      activity.NotificationType.system => 'general',
    };
  }

  static Future<List<NotificationItem>> _applyLocalReadStateAndDismissed(
    List<NotificationItem> raw,
    String? uid,
  ) async {
    final local = await activity.UserActivityService.getNotifications();
    final annRead = <String, bool>{};
    for (final n in local) {
      if (n.id.startsWith('ann_')) {
        annRead[n.id.substring(4)] = n.isRead;
      }
    }
    var next = raw.map((item) {
      if (!item.isAnnouncement) return item;
      final r = annRead[item.id];
      if (r == null) return item;
      return item.copyWith(isRead: r);
    }).toList();

    if (uid != null && uid.isNotEmpty) {
      final dismissed = await _loadDismissedAnnouncementIds(uid);
      next = next.where((i) {
        if (!i.isAnnouncement) return true;
        return !dismissed.contains(i.id);
      }).toList();
    }
    return next;
  }

  /// Unread count for nav badge — decreases when user marks items read.
  static Future<int> unreadCount({String? userId}) async {
    final items = await loadAlertItems(userId: userId);
    return items.where((i) => i.isUnread).length;
  }

  /// Firestore user notifications + published announcements (newest first).
  static Future<List<activity.AppNotification>> loadMergedForHome({
    String? userId,
  }) async {
    final items = await loadAlertItems(userId: userId);
    return items.map(_notificationItemToApp).toList();
  }

  static activity.AppNotification _notificationItemToApp(NotificationItem item) {
    return activity.AppNotification(
      id: item.isAnnouncement ? 'ann_${item.id}' : item.id,
      title: item.title,
      message: item.message,
      type: item.isAnnouncement
          ? _announcementTypeToActivity(item.type)
          : _userTypeToActivity(item.type),
      createdAt: item.createdAt,
      isRead: item.isRead,
      imageUrl: item.imageUrl,
      municipalityName: item.municipalityName,
    );
  }

  static activity.NotificationType _announcementTypeToActivity(String raw) {
    final t = raw.trim().toLowerCase();
    if (t == 'promo' || t == 'event') {
      return activity.NotificationType.event;
    }
    if (t == 'alert' || t == 'weather') {
      return activity.NotificationType.weather;
    }
    return activity.NotificationType.system;
  }

  static activity.NotificationType _userTypeToActivity(String raw) {
    final t = raw.trim().toLowerCase();
    if (t == 'welcome') return activity.NotificationType.welcome;
    if (t == 'checkin') return activity.NotificationType.checkin;
    if (t == 'badge') return activity.NotificationType.badge;
    if (t == 'event') return activity.NotificationType.event;
    if (t == 'weather') return activity.NotificationType.weather;
    return activity.NotificationType.system;
  }
}
