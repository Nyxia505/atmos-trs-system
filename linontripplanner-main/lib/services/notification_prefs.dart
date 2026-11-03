import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

const String _eventsTopic = 'tourism_events';

/// Per-user notification switches stored on `users/{uid}.notificationPrefs`.
class NotificationPrefs {
  final bool tripReminders;
  final bool spotUpdates;
  final bool events;

  const NotificationPrefs({
    this.tripReminders = true,
    this.spotUpdates = true,
    this.events = true,
  });

  factory NotificationPrefs.fromMap(Map<String, dynamic>? data) {
    bool on(String key) {
      final v = data?[key];
      if (v is bool) return v;
      return true;
    }

    return NotificationPrefs(
      tripReminders: on('tripReminders'),
      spotUpdates: on('spotUpdates'),
      events: on('events'),
    );
  }

  Map<String, bool> toMap() => {
        'tripReminders': tripReminders,
        'spotUpdates': spotUpdates,
        'events': events,
      };

  static Future<NotificationPrefs> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const NotificationPrefs();
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final raw = snap.data()?['notificationPrefs'];
    if (raw is Map) {
      return NotificationPrefs.fromMap(Map<String, dynamic>.from(raw));
    }
    return const NotificationPrefs();
  }

  static Future<void> save(NotificationPrefs prefs) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to save notification settings.');
    }
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'notificationPrefs': prefs.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await applyDelivery(prefs);
  }

  /// Event push uses the `tourism_events` topic. Other categories are stored
  /// so in-app alerts can honor them.
  static Future<void> applyDelivery(NotificationPrefs prefs) async {
    if (kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;
      if (prefs.events) {
        await messaging.subscribeToTopic(_eventsTopic);
      } else {
        await messaging.unsubscribeFromTopic(_eventsTopic);
      }
    } catch (e) {
      debugPrint('NotificationPrefs.applyDelivery: $e');
    }
  }
}
