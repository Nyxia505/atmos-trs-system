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
  /// so new users see past governor posts (not only pushes received after install).
  static Future<void> syncPublishedAnnouncementsToLocal({
    String? userId,
  }) async {
    try {
      final cutoff = await _registrationCutoff(userId);
      final announcements =
          await NotificationFirestoreService.getAnnouncements();
      for (final item in announcements) {
        if (cutoff != null && item.createdAt.isBefore(cutoff)) continue;
        await activity.UserActivityService.addNotificationFromAnnouncement(
          announcementId: item.id,
          title: item.title,
          message: item.message,
          type: _announcementTypeToActivity(item.type),
        );
      }
    } catch (e) {
      debugPrint('[AnnouncementNotificationSync] sync local: $e');
    }
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
    await syncPublishedAnnouncementsToLocal(userId: uid);
    final merged =
        await NotificationFirestoreService.getMergedNotifications(uid);
    return _applyLocalReadStateAndDismissed(merged, uid);
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
    if (t == 'checkin') return activity.NotificationType.checkin;
    if (t == 'badge') return activity.NotificationType.badge;
    if (t == 'event') return activity.NotificationType.event;
    if (t == 'weather') return activity.NotificationType.weather;
    return activity.NotificationType.system;
  }
}
