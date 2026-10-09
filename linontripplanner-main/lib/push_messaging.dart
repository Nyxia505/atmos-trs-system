import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

/// Same topic string as Cloud Function `EVENTS_FCM_TOPIC` in `functions/index.js`.
const String kEventsFcmTopic = 'tourism_events';

/// Must match AndroidManifest `default_notification_channel_id` and Cloud Function
/// `android.notification.channelId`.
const String kAndroidNotificationChannelId = 'tourism_events_channel';
const String kAndroidNotificationChannelName = 'Tourism events';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

int _foregroundNotificationId = 0;
bool _pushInitialized = false;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> _ensureAndroidChannel() async {
  final android = _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  if (android == null) return;
  await android.createNotificationChannel(
    const AndroidNotificationChannel(
      kAndroidNotificationChannelId,
      kAndroidNotificationChannelName,
      description: 'Alerts when new tourism events are published',
      importance: Importance.high,
      playSound: true,
    ),
  );
}

Future<void> _initLocalNotifications() async {
  if (kIsWeb) return;

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
    initSettings,
    onDidReceiveNotificationResponse: (_) {},
  );

  await _ensureAndroidChannel();

  final androidPlugin = _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();
}

String? _eventNotificationBodyFromData(Map<String, dynamic> data) {
  if (data['type'] != 'new_event') return null;
  final prebuilt = data['notificationBody']?.toString().trim();
  if (prebuilt != null && prebuilt.isNotEmpty) return prebuilt;

  final lines = <String>[];
  final municipality = data['municipality']?.toString().trim() ?? '';
  final venue = data['venue']?.toString().trim() ?? '';
  final location = <String>[
    if (municipality.isNotEmpty) municipality,
    if (venue.isNotEmpty) venue,
  ].join(' · ');
  if (location.isNotEmpty) lines.add(location);

  final time = data['time']?.toString().trim() ?? '';
  if (time.isNotEmpty) lines.add(time);

  final description = data['description']?.toString().trim() ?? '';
  if (description.isNotEmpty) lines.add(description);

  if (lines.isEmpty) return null;
  return lines.join('\n');
}

String _eventNotificationTitle(Map<String, dynamic> data, String? fallback) {
  if (data['type'] != 'new_event') return fallback ?? 'Notification';
  final name = data['title']?.toString().trim() ?? '';
  if (name.isNotEmpty) return 'New event: $name';
  if (fallback != null && fallback.trim().isNotEmpty) return fallback.trim();
  return 'New event';
}

void _showForegroundNotification(RemoteMessage message) {
  final n = message.notification;
  final data = message.data;
  final fromData = _eventNotificationBodyFromData(data);
  final title = _eventNotificationTitle(data, n?.title);
  final body = fromData ?? n?.body;
  if (body == null || body.isEmpty) return;
  final id = _foregroundNotificationId++;
  _localNotifications.show(
    id,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        kAndroidNotificationChannelId,
        kAndroidNotificationChannelName,
        channelDescription: 'Alerts when new tourism events are published',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

Future<void> _subscribeToEventsTopic(FirebaseMessaging messaging) async {
  // Token must exist before topic subscribe is reliable on some devices.
  String? token;
  for (var i = 0; i < 3; i++) {
    token = await messaging.getToken();
    if (token != null && token.isNotEmpty) break;
    await Future<void>.delayed(Duration(milliseconds: 400 * (i + 1)));
  }
  if (token == null || token.isEmpty) {
    debugPrint('initPushNotifications: no FCM token yet (will retry on refresh)');
  } else {
    debugPrint(
      'initPushNotifications: FCM token ready (${token.substring(0, 12)}…)',
    );
  }
  await messaging.subscribeToTopic(kEventsFcmTopic);
  debugPrint('initPushNotifications: subscribed to topic $kEventsFcmTopic');
}

/// Request notification permission, subscribe to [kEventsFcmTopic], and show
/// notifications while the app is in the foreground (FCM does not show system
/// banners on Android in that case).
///
/// No-op on web — system push requires a native Android/iOS install.
Future<void> initPushNotifications() async {
  if (kIsWeb) return;
  if (_pushInitialized) {
    // Re-subscribe in case token rotated while app stayed open.
    try {
      await _subscribeToEventsTopic(FirebaseMessaging.instance);
    } catch (e) {
      debugPrint('initPushNotifications re-subscribe: $e');
    }
    return;
  }
  try {
    await _initLocalNotifications();

    final messaging = FirebaseMessaging.instance;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint(
      'initPushNotifications: permission=${settings.authorizationStatus}',
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint(
        'initPushNotifications: notification permission denied — '
        'enable in system Settings to receive event alerts',
      );
    }

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    messaging.onTokenRefresh.listen((_) {
      _subscribeToEventsTopic(messaging);
    });

    await _subscribeToEventsTopic(messaging);
    _pushInitialized = true;
  } catch (e, st) {
    debugPrint('initPushNotifications: $e\n$st');
  }
}
