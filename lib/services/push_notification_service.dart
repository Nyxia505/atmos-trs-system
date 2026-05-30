import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atmos_trs_system/services/announcement_notification_sync.dart';
import 'package:atmos_trs_system/services/notification_badge_notifier.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart' as activity;

/// FCM topic all tourist apps subscribe to — must match [functions/index.js].
const String kGovernorAnnouncementsTopic = 'governor_announcements';

/// Android channel for admin / Tourism Office announcements — must match [functions/index.js] `android.notification.channelId`.
const String kAndroidAnnouncementChannelId = 'atmos_announcement_heads_up';

const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
  'atmos_high_importance',
  'ATMOS announcements',
  description: 'Governor & tourism promos, events, and alerts',
  importance: Importance.high,
);

/// Same priority as OTP: heads-up banner + full text in shade (BigText).
const AndroidNotificationChannel _androidAnnouncementHeadsUpChannel =
    AndroidNotificationChannel(
  kAndroidAnnouncementChannelId,
  'ATMOS Tourism announcements',
  description: 'Tourism Office & governor alerts — same priority as OTP',
  importance: Importance.max,
);

/// Heads-up channel: OTP looks like an email preview in the shade (no Gmail app).
const AndroidNotificationChannel _androidOtpChannel = AndroidNotificationChannel(
  'atmos_otp_email_style',
  'ATMOS-TRS OTP',
  description: 'Verification codes — shown here so you do not need to open Gmail',
  importance: Importance.max,
);

/// Stable id so a new code replaces the previous OTP notification.
const int kAtmosOtpNotificationId = 919001;
const int kAtmosPasswordResetNotificationId = 919002;

StreamSubscription<RemoteMessage>? _passwordResetForegroundSubscription;

String _otpBigTextBody(String otp, String? displayName) {
  final name = displayName?.trim();
  final greeting =
      (name != null && name.isNotEmpty) ? 'Hello $name,' : 'Hello,';
  return '$greeting\n\n'
      'Your ATMOS verification code is: $otp\n\n'
      'This code will expire in 5 minutes.\n\n'
      'If this wasn\'t you, please ignore this message.\n\n'
      '— ATMOS TRS';
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

bool _localNotificationsReady = false;
bool _touristPushRegistered = false;
StreamSubscription<RemoteMessage>? _onMessageSubscription;
StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    _announcementFallbackSubscription;
String? _lastSeenPublishedAnnouncementId;
const String _kLastSeenAnnouncementIdPref = 'push_last_seen_announcement_id';

/// Avoids duplicate banners when both FCM topic push and Firestore fallback fire.
final List<String> _announcementDedupIds = [];
const int _maxAnnouncementDedupIds = 48;

bool _tryMarkAnnouncementShown(String id) {
  if (id.isEmpty) return true;
  if (_announcementDedupIds.contains(id)) return false;
  _announcementDedupIds.add(id);
  while (_announcementDedupIds.length > _maxAnnouncementDedupIds) {
    _announcementDedupIds.removeAt(0);
  }
  return true;
}

bool _fcmTokenRefreshLinked = false;

Future<void> _persistLastSeenAnnouncementId(String id) async {
  if (id.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastSeenAnnouncementIdPref, id);
  } catch (_) {}
}

Future<String?> _readLastSeenAnnouncementId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kLastSeenAnnouncementIdPref);
    if (id == null || id.isEmpty) return null;
    return id;
  } catch (_) {
    return null;
  }
}

/// Initializes notification permission, Android channels, and [FlutterLocalNotificationsPlugin].
/// Safe to call multiple times (subsequent calls are mostly no-ops).
Future<void> _ensureLocalNotificationsCore() async {
  if (kIsWeb || Firebase.apps.isEmpty) return;

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
    await androidPlugin?.createNotificationChannel(_androidAnnouncementHeadsUpChannel);
    await androidPlugin?.createNotificationChannel(_androidOtpChannel);
    await androidPlugin?.requestNotificationsPermission();
  }

  if (!_localNotificationsReady) {
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
  }
}

void _wireFcmTokenRefreshToFirestore() {
  if (kIsWeb || _fcmTokenRefreshLinked) return;
  _fcmTokenRefreshLinked = true;
  FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[Push] token refresh save failed: $e');
    }
  });
}

/// Call from signup / verify-otp so FCM can target this device (optional server pushes).
Future<void> syncFcmTokenToUserDoc(String uid) async {
  if (kIsWeb || uid.isEmpty || Firebase.apps.isEmpty) return;
  try {
    await _ensureLocalNotificationsCore();
    _wireFcmTokenRefreshToFirestore();
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  } catch (e) {
    debugPrint('[Push] sync FCM token failed: $e');
  }
}

/// Ensures local notifications work for OTP before the tourist main shell opens.
Future<void> ensureEmailOtpNotificationSupport() async {
  if (kIsWeb || Firebase.apps.isEmpty) return;
  try {
    await _ensureLocalNotificationsCore();
    _wireFcmTokenRefreshToFirestore();
  } catch (e, st) {
    debugPrint('[Push] ensureEmailOtpNotificationSupport: $e\n$st');
  }
}

/// Shows the 6-digit code in the shade like a Gmail-style OTP preview (Android BigText / iOS banner).
Future<void> showEmailOtpLocalNotification(
  String otp, {
  String? displayName,
}) async {
  if (kIsWeb || Firebase.apps.isEmpty) return;
  final digits = otp.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 6) return;

  try {
    await ensureEmailOtpNotificationSupport();
    if (!_localNotificationsReady) return;

    final bigText = _otpBigTextBody(digits, displayName);
    final collapsed =
        'Your ATMOS verification code is: $digits. Expires in 5 minutes.';

    final android = AndroidNotificationDetails(
      _androidOtpChannel.id,
      _androidOtpChannel.name,
      channelDescription: _androidOtpChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
      ticker: 'ATMOS-TRS OTP code',
      styleInformation: BigTextStyleInformation(
        bigText,
        contentTitle: 'ATMOS-TRS OTP code',
        summaryText: 'ATMOS TRS',
      ),
      icon: '@mipmap/ic_launcher',
    );
    final ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
      subtitle: 'Code $digits · Expires in 5 min',
      interruptionLevel: InterruptionLevel.active,
    );
    final details = NotificationDetails(android: android, iOS: ios);

    await _localNotifications.show(
      id: kAtmosOtpNotificationId,
      title: 'ATMOS-TRS',
      body: collapsed,
      notificationDetails: details,
    );
  } catch (e, st) {
    debugPrint('[Push] showEmailOtpLocalNotification: $e\n$st');
  }
}

/// Listens for password-reset OTP pushes while on the forgot-password screen.
Future<void> ensurePasswordResetNotificationSupport({
  void Function(String otp)? onOtpFromPush,
}) async {
  if (kIsWeb || Firebase.apps.isEmpty) return;
  try {
    await _ensureLocalNotificationsCore();
    await _passwordResetForegroundSubscription?.cancel();
    _passwordResetForegroundSubscription =
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['type']?.toString() != 'password_reset_otp') return;
      final otp = message.data['otp']?.toString() ?? '';
      if (otp.replaceAll(RegExp(r'\D'), '').length != 6) return;
      final digits = otp.replaceAll(RegExp(r'\D'), '');
      final name = message.data['displayName']?.toString();
      unawaited(showPasswordResetOtpLocalNotification(digits, displayName: name));
      onOtpFromPush?.call(digits);
    });
  } catch (e, st) {
    debugPrint('[Push] ensurePasswordResetNotificationSupport: $e\n$st');
  }
}

Future<void> disposePasswordResetNotificationSupport() async {
  await _passwordResetForegroundSubscription?.cancel();
  _passwordResetForegroundSubscription = null;
}

/// Heads-up notification for password reset OTP (same channel as email verification).
Future<void> showPasswordResetOtpLocalNotification(
  String otp, {
  String? displayName,
}) async {
  if (kIsWeb || Firebase.apps.isEmpty) return;
  final digits = otp.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 6) return;

  try {
    await _ensureLocalNotificationsCore();
    if (!_localNotificationsReady) return;

    final name = displayName?.trim();
    final greeting =
        (name != null && name.isNotEmpty) ? 'Hello $name,' : 'Hello,';
    final bigText = '$greeting\n\n'
        'Your ATMOS password reset code is: $digits\n\n'
        'This code will expire in 5 minutes.\n\n'
        'If this wasn\'t you, please ignore this message.\n\n'
        '— ATMOS TRS';
    final collapsed =
        'Your password reset code is $digits. Expires in 5 minutes.';

    final android = AndroidNotificationDetails(
      _androidOtpChannel.id,
      _androidOtpChannel.name,
      channelDescription: _androidOtpChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
      ticker: 'ATMOS-TRS password reset',
      styleInformation: BigTextStyleInformation(
        bigText,
        contentTitle: 'ATMOS-TRS password reset',
        summaryText: 'ATMOS TRS',
      ),
      icon: '@mipmap/ic_launcher',
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
      subtitle: 'Reset code · Expires in 5 min',
      interruptionLevel: InterruptionLevel.active,
    );
    final details = NotificationDetails(android: android, iOS: ios);

    await _localNotifications.show(
      id: kAtmosPasswordResetNotificationId,
      title: 'ATMOS-TRS',
      body: collapsed,
      notificationDetails: details,
    );
  } catch (e, st) {
    debugPrint('[Push] showPasswordResetOtpLocalNotification: $e\n$st');
  }
}

/// Saves OTP to Firestore should already be done — this delivers the code on-device + syncs FCM.
Future<void> deliverEmailOtpToDevice({
  required String uid,
  required String otp,
  String? displayName,
}) async {
  if (kIsWeb) return;
  await syncFcmTokenToUserDoc(uid);
  await showEmailOtpLocalNotification(otp, displayName: displayName);
}

/// Tourism Office / governor announcement — heads-up + BigText (parity with OTP UX).
Future<void> _showAnnouncementHeadsUpLocal({
  required String announcementId,
  required String title,
  required String body,
}) async {
  if (!_localNotificationsReady || kIsWeb) return;
  if (!_tryMarkAnnouncementShown(announcementId)) return;

  final trimmedTitle = title.trim().isEmpty ? 'ATMOS TRS' : title.trim();
  final full = body.trim();
  final bigBody =
      full.length > 800 ? '${full.substring(0, 797)}...' : full;
  final collapsed =
      full.length > 140 ? '${full.substring(0, 137)}...' : full;

  final android = AndroidNotificationDetails(
    kAndroidAnnouncementChannelId,
    _androidAnnouncementHeadsUpChannel.name,
    channelDescription: _androidAnnouncementHeadsUpChannel.description,
    importance: Importance.max,
    priority: Priority.max,
    visibility: NotificationVisibility.public,
    category: AndroidNotificationCategory.message,
    ticker: trimmedTitle,
    styleInformation: BigTextStyleInformation(
      bigBody.isEmpty ? trimmedTitle : bigBody,
      contentTitle: trimmedTitle,
      summaryText: 'ATMOS TRS',
    ),
    icon: '@mipmap/ic_launcher',
  );
  const ios = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    presentBanner: true,
    presentList: true,
    subtitle: 'Tourism Office announcement',
    interruptionLevel: InterruptionLevel.active,
  );
  final details = NotificationDetails(android: android, iOS: ios);

  final nid = 919010 + (announcementId.hashCode.abs() % 989989);
  await _localNotifications.show(
    id: nid,
    title: trimmedTitle,
    body: collapsed.isEmpty ? 'New announcement' : collapsed,
    notificationDetails: details,
  );
}

activity.NotificationType _announcementTypeToActivityType(String rawType) {
  final t = rawType.trim().toLowerCase();
  if (t == 'promo' || t == 'event') return activity.NotificationType.event;
  if (t == 'alert' || t == 'weather') return activity.NotificationType.weather;
  return activity.NotificationType.system;
}

Future<void> _mirrorAnnouncementToUserActivity({
  required String announcementId,
  required String title,
  required String body,
  required String type,
}) async {
  if (announcementId.isEmpty) return;
  await activity.UserActivityService.addNotificationFromAnnouncement(
    announcementId: announcementId,
    title: title,
    message: body,
    type: _announcementTypeToActivityType(type),
  );
}

/// Shows a system notification when a push arrives while the app is in the foreground.
Future<void> _showForegroundNotification(RemoteMessage message) async {
  if (!_localNotificationsReady || kIsWeb) return;
  final notification = message.notification;
  final aid = message.data['announcementId']?.toString() ?? '';
  final title = notification?.title ??
      message.data['title']?.toString() ??
      'ATMOS TRS';
  final body = notification?.body ??
      message.data['body']?.toString() ??
      'New announcement';

  if (aid.isNotEmpty) {
    await _mirrorAnnouncementToUserActivity(
      announcementId: aid,
      title: title,
      body: body,
      type: message.data['type']?.toString() ?? 'General',
    );
    await _showAnnouncementHeadsUpLocal(
      announcementId: aid,
      title: title,
      body: body,
    );
    await NotificationBadgeNotifier.instance.refresh();
    return;
  }

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

    await _ensureLocalNotificationsCore();
    _wireFcmTokenRefreshToFirestore();

    final messaging = FirebaseMessaging.instance;
    await messaging.subscribeToTopic(kGovernorAnnouncementsTopic);
    debugPrint('[Push] subscribed to topic $kGovernorAnnouncementsTopic');

    await _onMessageSubscription?.cancel();
    _onMessageSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final t = message.data['type']?.toString();
      if (t == 'email_otp') {
        final otp = message.data['otp']?.toString() ?? '';
        if (otp.replaceAll(RegExp(r'\D'), '').length == 6) {
          showEmailOtpLocalNotification(otp.replaceAll(RegExp(r'\D'), ''));
          return;
        }
      }
      if (t == 'password_reset_otp') {
        final otp = message.data['otp']?.toString() ?? '';
        if (otp.replaceAll(RegExp(r'\D'), '').length == 6) {
          final digits = otp.replaceAll(RegExp(r'\D'), '');
          showPasswordResetOtpLocalNotification(
            digits,
            displayName: message.data['displayName']?.toString(),
          );
          return;
        }
      }
      debugPrint('[Push] foreground: ${message.notification?.title}');
      _showForegroundNotification(message);
    });

    _touristPushRegistered = true;
    _startAnnouncementFallbackListener();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await AnnouncementNotificationSync.syncPublishedAnnouncementsToLocal(
        userId: uid,
      );
    }
  } catch (e, st) {
    debugPrint('[Push] register failed: $e\n$st');
  }
}

/// Fallback while app is open: watches newly published announcements and shows
/// a local notification even if server push is not configured yet.
void _startAnnouncementFallbackListener() {
  if (kIsWeb) return;
  if (_announcementFallbackSubscription != null) return;
  if (Firebase.apps.isEmpty) return;
  unawaited(() async {
    _lastSeenPublishedAnnouncementId ??= await _readLastSeenAnnouncementId();
    final query = FirebaseFirestore.instance
        .collection('announcements')
        .where('published', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(1);

    _announcementFallbackSubscription = query.snapshots().listen((snapshot) async {
      if (snapshot.docs.isEmpty) return;
      final latest = snapshot.docs.first;
      final id = latest.id;
      final data = latest.data();

      final shouldNotify = _lastSeenPublishedAnnouncementId == null ||
          _lastSeenPublishedAnnouncementId != id;
      _lastSeenPublishedAnnouncementId = id;
      await _persistLastSeenAnnouncementId(id);
      if (!shouldNotify) return;

      final title = (data['title'] as String?)?.trim();
      final content =
          (data['content'] as String?)?.trim() ?? (data['message'] as String?)?.trim() ?? '';

      if (!_localNotificationsReady) return;
      await _mirrorAnnouncementToUserActivity(
        announcementId: id,
        title: (title == null || title.isEmpty) ? 'ATMOS TRS' : title,
        body: content.isEmpty ? 'New announcement' : content,
        type: data['type']?.toString() ?? 'General',
      );
      await _showAnnouncementHeadsUpLocal(
        announcementId: id,
        title: (title == null || title.isEmpty) ? 'ATMOS TRS' : title,
        body: content.isEmpty ? 'New announcement' : content,
      );
      await NotificationBadgeNotifier.instance.refresh();
    }, onError: (e) {
      debugPrint('[Push] announcement fallback listen error: $e');
    });
  }());
}

/// Unsubscribe on logout (optional).
Future<void> unregisterTouristPushTopic() async {
  if (kIsWeb) return;
  try {
    await _onMessageSubscription?.cancel();
    _onMessageSubscription = null;
    await _announcementFallbackSubscription?.cancel();
    _announcementFallbackSubscription = null;
    _lastSeenPublishedAnnouncementId = null;
    _announcementDedupIds.clear();
    await FirebaseMessaging.instance.unsubscribeFromTopic(kGovernorAnnouncementsTopic);
    _touristPushRegistered = false;
  } catch (e) {
    debugPrint('[Push] unsubscribe: $e');
  }
}
