import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/navigation/pending_checkin_navigation.dart';
import 'package:atmos_trs_system/navigation/root_navigator.dart';
import 'package:atmos_trs_system/services/qr_launch_bootstrap.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles phone-camera / App Link QR URLs on native, plus Play install referrer.
class CameraQrDeepLinkService {
  CameraQrDeepLinkService._();

  static const _kReferrerConsumed = 'atmos_play_install_referrer_consumed';

  static StreamSubscription<Uri>? _sub;
  static bool _started = false;

  /// Call once after Firebase init (native only).
  static Future<void> start() async {
    if (kIsWeb || _started) return;
    _started = true;

    if (Platform.isAndroid) {
      await _applyInstallReferrerOnce();
    }

    final appLinks = AppLinks();
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) {
        await _handleUri(initial, fromColdStart: true);
      }
    } catch (e, st) {
      debugPrint('[CameraQrDeepLink] getInitialLink failed: $e\n$st');
    }

    _sub = appLinks.uriLinkStream.listen(
      (uri) => unawaited(_handleUri(uri, fromColdStart: false)),
      onError: (Object e, StackTrace st) {
        debugPrint('[CameraQrDeepLink] uri stream error: $e\n$st');
      },
    );
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }

  static Future<void> _applyInstallReferrerOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kReferrerConsumed) == true) return;

      final details = await PlayInstallReferrer.installReferrer;
      final referrer = (details.installReferrer ?? '').trim();
      await prefs.setBool(_kReferrerConsumed, true);

      if (referrer.isEmpty) return;
      final url = QrLaunchBootstrap.checkInUrlFromInstallReferrer(referrer);
      if (url == null) return;
      debugPrint('[CameraQrDeepLink] install referrer → $url');
      await QrLaunchBootstrap.applyFromRawUrl(url);
    } catch (e, st) {
      debugPrint('[CameraQrDeepLink] install referrer skipped: $e\n$st');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kReferrerConsumed, true);
      } catch (_) {}
    }
  }

  static Future<void> _handleUri(Uri uri, {required bool fromColdStart}) async {
    final raw = uri.toString();
    debugPrint('[CameraQrDeepLink] handle uri=$raw cold=$fromColdStart');
    final applied = await QrLaunchBootstrap.applyFromRawUrl(raw);
    if (!applied) return;

    // Cold start: StartupRouteResolver picks /qr-welcome or /qr-resume.
    if (fromColdStart) return;

    await _navigateForPendingIfReady();
  }

  static Future<void> _navigateForPendingIfReady() async {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;

    final user = FirebaseAuth.instance.currentUser;
    final uid = AuthConfig.currentUserUid ?? user?.uid;
    final role = await SessionStorage.getStoredRole();

    if (uid == null || uid.isEmpty || user == null) {
      nav.pushNamedAndRemoveUntil('/qr-welcome', (r) => false);
      return;
    }

    if (role != UserRole.tourist) {
      debugPrint('[CameraQrDeepLink] ignore QR for non-tourist role=$role');
      return;
    }

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      nav.pushNamedAndRemoveUntil('/qr-resume', (r) => false);
      return;
    }

    await navigateToPendingSpotCheckInOrDashboard(
      ctx,
      defaultRoute: '/dashboard',
      isTouristDestination: true,
      preferLandingAfterPendingCheckIn: false,
    );
  }
}
