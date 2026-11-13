import 'package:atmos_trs_system/services/lgu_event_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/models/notification_item.dart';
import 'package:atmos_trs_system/services/welcome_notification_service.dart';

const String _notificationsCollection = 'notifications';
const String _announcementsCollection = 'announcements';

/// Firestore-based notifications: user-specific notifications and general announcements.
class NotificationFirestoreService {
  NotificationFirestoreService._();

  static bool get _isFirebaseInitialized {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Creates a welcome notification for a user after sign-up (once per user).
  static Future<void> createWelcomeNotification(
    String userId, {
    String? firstName,
  }) async {
    if (!_isFirebaseInitialized || userId.isEmpty) return;
    try {
      final existing = await _firestore
          .collection(_notificationsCollection)
          .where('user_id', isEqualTo: userId)
          .where('type', isEqualTo: 'welcome')
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return;

      final copy = WelcomeNotificationService.welcomeCopy(firstName);

      await _firestore.collection(_notificationsCollection).add({
        'user_id': userId,
        'title': copy.title,
        'message': copy.message,
        'type': 'welcome',
        'created_at': FieldValue.serverTimestamp(),
        'is_read': false,
      });
    } catch (e) {
      debugPrint('NotificationFirestoreService.createWelcomeNotification: $e');
    }
  }

  /// Creates a check-in notification after successful QR check-in.
  static Future<void> createCheckInNotification(String userId, String spotName) async {
    if (!_isFirebaseInitialized || userId.isEmpty) return;
    try {
      final message = spotName.trim().isNotEmpty
          ? 'Check-in successful! You checked in at $spotName.'
          : 'Check-in successful! Your visit has been recorded.';
      await _firestore.collection(_notificationsCollection).add({
        'user_id': userId,
        'title': 'Check-in recorded',
        'message': message,
        'type': 'checkin',
        'created_at': FieldValue.serverTimestamp(),
        'is_read': false,
      });
    } catch (e) {
      assert(true, 'createCheckInNotification: $e');
    }
  }

  /// Notifies an establishment owner after OPTACA approve / reject / revision.
  /// Dedupes by `type` + `establishmentId` + `status` so re-saves do not spam.
  static Future<void> createEstablishmentDecisionNotification({
    required String userId,
    required String businessName,
    required String status,
    String reviewNotes = '',
  }) async {
    if (!_isFirebaseInitialized || userId.isEmpty) return;
    final normalized = status.trim().toLowerCase();
    if (normalized.isEmpty) return;
    try {
      // One notice per status outcome (approved / rejected / needs_revision).
      final dedupeType = 'establishment_$normalized';
      final existing = await _firestore
          .collection(_notificationsCollection)
          .where('user_id', isEqualTo: userId)
          .where('type', isEqualTo: dedupeType)
          .where('establishment_id', isEqualTo: userId)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return;

      final name = businessName.trim().isEmpty ? 'Your establishment' : businessName.trim();
      final notes = reviewNotes.trim();
      final String title;
      final String message;
      switch (normalized) {
        case 'active':
        case 'approved':
          title = 'Registration approved';
          message =
              '$name is approved. You can now open your Establishment Dashboard.';
          break;
        case 'rejected':
          title = 'Registration rejected';
          message = notes.isEmpty
              ? 'OPTACA did not approve $name. Sign in to view details.'
              : 'OPTACA rejected $name: $notes';
          break;
        case 'needs_revision':
          title = 'Corrections requested';
          message = notes.isEmpty
              ? 'OPTACA asked for corrections on $name. Sign in to review.'
              : 'OPTACA requested corrections for $name: $notes';
          break;
        default:
          title = 'Registration update';
          message = 'OPTACA updated the status of $name to $normalized.';
      }

      await _firestore.collection(_notificationsCollection).add({
        'user_id': userId,
        'title': title,
        'message': message,
        'type': dedupeType,
        'status': normalized,
        'establishment_id': userId,
        'created_at': FieldValue.serverTimestamp(),
        'is_read': false,
      });
    } catch (e) {
      debugPrint(
        'NotificationFirestoreService.createEstablishmentDecisionNotification: $e',
      );
    }
  }

  /// Creates a one-time OPTACA inbox alert for a new AE registration.
  static Future<void> createOptacaEstablishmentRegistrationAlert({
    required String establishmentId,
    required String businessName,
    required String municipality,
  }) async {
    if (!_isFirebaseInitialized || establishmentId.isEmpty) return;
    try {
      final ref = _firestore
          .collection('optaca_alerts')
          .doc('est_reg_$establishmentId');
      final existing = await ref.get();
      if (existing.exists) return;
      await ref.set({
        'type': 'establishment_registration',
        'establishmentId': establishmentId,
        'businessName': businessName.trim(),
        'municipality': municipality.trim(),
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
        'is_read': false,
        'action': 'open_establishment_review',
      });
    } catch (e) {
      debugPrint(
        'NotificationFirestoreService.createOptacaEstablishmentRegistrationAlert: $e',
      );
    }
  }

  /// Marks the OPTACA registration alert resolved after a decision.
  static Future<void> resolveOptacaEstablishmentRegistrationAlert(
    String establishmentId, {
    required String status,
  }) async {
    if (!_isFirebaseInitialized || establishmentId.isEmpty) return;
    try {
      final ref = _firestore
          .collection('optaca_alerts')
          .doc('est_reg_$establishmentId');
      final snap = await ref.get();
      if (!snap.exists) return;
      await ref.set({
        'status': status.trim().toLowerCase(),
        'is_read': true,
        'resolved_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint(
        'NotificationFirestoreService.resolveOptacaEstablishmentRegistrationAlert: $e',
      );
    }
  }

  /// Fetches user-specific notifications for [userId], newest first.
  static Future<List<NotificationItem>> getUserNotifications(String userId) async {
    if (!_isFirebaseInitialized || userId.isEmpty) return [];
    try {
      final snapshot = await _firestore
          .collection(_notificationsCollection)
          .where('user_id', isEqualTo: userId)
          .limit(50)
          .get();
      final list = snapshot.docs.map((d) => _docToNotificationItem(d, isAnnouncement: false)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      return [];
    }
  }

  /// Fetches published announcements, newest first.
  static Future<List<NotificationItem>> getAnnouncements() async {
    if (!_isFirebaseInitialized) return [];
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await _firestore
            .collection(_announcementsCollection)
            .where('published', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .limit(30)
            .get();
      } catch (_) {
        snapshot = await _firestore
            .collection(_announcementsCollection)
            .where('published', isEqualTo: true)
            .limit(30)
            .get();
      }
      final list = snapshot.docs
          .where((d) => LguEventService.isVisibleToTourists(d.data()))
          .map(_announcementDocToItem)
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      return [];
    }
  }

  /// Merges user notifications and announcements and sorts by newest first.
  /// Drops activity rows that duplicate a published announcement (same title+body).
  static Future<List<NotificationItem>> getMergedNotifications(String? userId) async {
    final List<NotificationItem> list = [];
    if (userId != null && userId.isNotEmpty) {
      list.addAll(await getUserNotifications(userId));
    }
    final announcements = await getAnnouncements();
    list.addAll(announcements);

    final announcementKeys = <String>{
      for (final a in announcements) _dedupeKey(a.title, a.message),
    };
    final deduped = <NotificationItem>[];
    final seenIds = <String>{};
    for (final item in list) {
      if (!seenIds.add(item.id)) continue;
      if (!item.isAnnouncement &&
          announcementKeys.contains(_dedupeKey(item.title, item.message))) {
        continue;
      }
      deduped.add(item);
    }
    deduped.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return deduped;
  }

  static String _dedupeKey(String title, String message) {
    return '${title.trim().toLowerCase()}|${message.trim().toLowerCase()}';
  }

  /// Marks a user notification as read.
  static Future<void> markAsRead(String notificationId) async {
    if (!_isFirebaseInitialized || notificationId.isEmpty) return;
    try {
      await _firestore.collection(_notificationsCollection).doc(notificationId).update({'is_read': true});
    } catch (_) {}
  }

  /// Marks every Firestore notification for [userId] as read (batched).
  static Future<void> markAllAsReadForUser(String userId) async {
    if (!_isFirebaseInitialized || userId.isEmpty) return;
    try {
      final snap = await _firestore
          .collection(_notificationsCollection)
          .where('user_id', isEqualTo: userId)
          .limit(100)
          .get();
      if (snap.docs.isEmpty) return;
      var batch = _firestore.batch();
      var ops = 0;
      for (final d in snap.docs) {
        final data = d.data();
        if (data['is_read'] == true) continue;
        batch.update(d.reference, {'is_read': true});
        ops++;
        if (ops >= 450) {
          await batch.commit();
          batch = _firestore.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
    } catch (e) {
      debugPrint('NotificationFirestoreService.markAllAsReadForUser: $e');
    }
  }

  /// Removes a user-owned notification document.
  static Future<void> deleteUserNotification(String notificationId) async {
    if (!_isFirebaseInitialized || notificationId.isEmpty) return;
    try {
      await _firestore.collection(_notificationsCollection).doc(notificationId).delete();
    } catch (e) {
      debugPrint('NotificationFirestoreService.deleteUserNotification: $e');
    }
  }

  static NotificationItem _docToNotificationItem(DocumentSnapshot<Map<String, dynamic>> d, {required bool isAnnouncement}) {
    final data = d.data() ?? {};
    final created = data['created_at'];
    DateTime createdAt = DateTime.now();
    if (created is Timestamp) {
      createdAt = created.toDate();
    } else if (created is DateTime) {
      createdAt = created;
    }
    return NotificationItem(
      id: d.id,
      title: data['title'] as String? ?? 'Notification',
      message: data['message'] as String? ?? '',
      type: data['type'] as String? ?? 'general',
      createdAt: createdAt,
      isRead: data['is_read'] as bool? ?? false,
      userId: data['user_id'] as String?,
      isAnnouncement: isAnnouncement,
    );
  }

  static NotificationItem _announcementDocToItem(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    final created = data['createdAt'] ?? data['created_at'];
    DateTime createdAt = DateTime.now();
    if (created is Timestamp) {
      createdAt = created.toDate();
    } else if (created is DateTime) {
      createdAt = created;
    }
    final message = data['content'] as String? ?? data['message'] as String? ?? '';
    final municipalityName = data['municipalityName']?.toString().trim();
    final resolvedImage = LguEventService.resolveDisplayImage(data);
    return NotificationItem(
      id: d.id,
      title: data['title'] as String? ?? 'Announcement',
      message: message,
      type: data['type'] as String? ?? 'General',
      createdAt: createdAt,
      // Per-user read state is applied in [AlertsTabPage] from local prefs.
      isRead: false,
      userId: null,
      isAnnouncement: true,
      imageUrl: resolvedImage,
      municipalityName:
          (municipalityName != null && municipalityName.isNotEmpty)
              ? municipalityName
              : null,
    );
  }
}
