import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// FCM topic all tourist apps subscribe to — must match [functions/index.js].
const String kGovernorAnnouncementsTopic = 'governor_announcements';

const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
  'atmos_high_importance',
  'ATMOS announcements',
  description: 'Governor & tourism promos, events, and alerts',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

bool _localNotificationsReady = false;
bool _touristPushRegistered = false;
StreamSubscription<RemoteMessage>? _onMessageSubscription;

/// Shows a system notification when a push arrives while the app is in the foreground.
Future<void> _showForegroundNotification(RemoteMessage message) async {
  if (!_localNotificationsReady || kIsWeb) return;
  final notification = message.notification;
  final title = notification?.title ?? message.data['title'] as String? ?? 'ATMOS TRS';
  final body = notification?.body ??
      message.data['body'] as String? ??
      'New announcement';

  const android = AndroidNotificationDetails(
    'atmos_high_importance',
    'ATMOS announcements',
    channelDescription: 'Governor & tourism promos, events, and alerts',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );
  const details = NotificationDetails(android: android);

  await _localNotifications.show(
    id: message.hashCode,
    title: title,
    body: body,
    notificationDetails: details,
  );
}

/// Registers FCM: permission, local notification plugin, topic subscription, and listeners.
/// Call when the tourist main shell opens (not on web — use in-app notifications only there).
Future<void> registerTouristPushNotifications() async {
  if (kIsWeb) return;
  if (_touristPushRegistered) return;
  try {
    if (Firebase.apps.isEmpty) return;

    final messaging = FirebaseMessaging.instance;

    if (Platform.isIOS) {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_androidChannel);
      await androidPlugin?.requestNotificationsPermission();
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (_) {},
    );
    _localNotificationsReady = true;

    await messaging.subscribeToTopic(kGovernorAnnouncementsTopic);
    debugPrint('[Push] subscribed to topic $kGovernorAnnouncementsTopic');

    await _onMessageSubscription?.cancel();
    _onMessageSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[Push] foreground: ${message.notification?.title}');
      _showForegroundNotification(message);
    });

    messaging.onTokenRefresh.listen((token) {
      debugPrint('[Push] FCM token refreshed');
    });
    _touristPushRegistered = true;
  } catch (e, st) {
    debugPrint('[Push] register failed: $e\n$st');
  }
}

/// Unsubscribe on logout (optional).
Future<void> unregisterTouristPushTopic() async {
  if (kIsWeb) return;
  try {
    await _onMessageSubscription?.cancel();
    _onMessageSubscription = null;
    await FirebaseMessaging.instance.unsubscribeFromTopic(kGovernorAnnouncementsTopic);
    _touristPushRegistered = false;
  } catch (e) {
    debugPrint('[Push] unsubscribe: $e');
  }
}
