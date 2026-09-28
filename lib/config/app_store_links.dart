// Public store / download URLs for the ATMOS TRS mobile app.
// Replace placeholders when listings and APK hosting are live.

import 'package:atmos_trs_system/services/qr_launch_bootstrap.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const String kGooglePlayStoreAppUrl =
    'https://play.google.com/store/apps/details?id=com.atmos.trs';

const String kAppStoreAppUrl =
    'https://apps.apple.com/app/id0000000000';

/// Direct Android APK download (Firebase Hosting, GitHub Releases, etc.).
/// Leave empty to hide the APK button until a file is hosted.
const String kAndroidApkDownloadUrl =
    'https://github.com/Nyxia505/atmos-trs-system/releases/latest/download/atmos-trs.apk';

bool get kHasAndroidApkDownload => kAndroidApkDownloadUrl.trim().isNotEmpty;

/// Play Store URL with install referrer so first open can resume the scanned QR.
String googlePlayStoreUrlWithQrReferrer(String? checkInUrl) {
  final base = Uri.parse(kGooglePlayStoreAppUrl);
  if (checkInUrl == null || checkInUrl.trim().isEmpty) {
    return base.toString();
  }
  final parsed = Uri.tryParse(checkInUrl.trim());
  final q = parsed == null
      ? ''
      : (parsed.hasQuery
          ? parsed.query
          : mergedQueryFromCheckIn(checkInUrl));
  if (q.isEmpty) return base.toString();

  final referrer = Uri(queryParameters: {
    'utm_source': 'atmos_qr',
    'utm_medium': 'camera',
    'atmos_q': q,
  }).query;

  return base.replace(queryParameters: {
    ...base.queryParameters,
    'referrer': referrer,
  }).toString();
}

String mergedQueryFromCheckIn(String checkInUrl) {
  final uri = Uri.tryParse(checkInUrl);
  if (uri == null) return '';
  if (uri.hasQuery) return uri.query;
  // Legacy hash: #/landing?type=…
  final frag = uri.fragment;
  final qi = frag.indexOf('?');
  if (qi >= 0) return frag.substring(qi + 1);
  return '';
}

/// Opens store / APK, embedding pending QR in Play referrer when available.
Future<bool> openAtmosAppDownload({
  required AtmosAppDownloadTarget target,
  bool copyCheckInLinkToClipboard = true,
}) async {
  final pendingUrl = await QrLaunchBootstrap.pendingAsCheckInUrl();
  if (copyCheckInLinkToClipboard &&
      pendingUrl != null &&
      pendingUrl.isNotEmpty) {
    try {
      await Clipboard.setData(ClipboardData(text: pendingUrl));
    } catch (_) {}
  }

  final String url;
  switch (target) {
    case AtmosAppDownloadTarget.playStore:
      url = googlePlayStoreUrlWithQrReferrer(pendingUrl);
    case AtmosAppDownloadTarget.apk:
      url = kAndroidApkDownloadUrl;
    case AtmosAppDownloadTarget.appStore:
      url = kAppStoreAppUrl;
  }

  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

enum AtmosAppDownloadTarget { playStore, apk, appStore }

/// Best-effort: open the native app via https App Link when installed (web only).
Future<bool> tryOpenAtmosAppWithPendingQr() async {
  if (!kIsWeb) return false;
  final pendingUrl = await QrLaunchBootstrap.pendingAsCheckInUrl();
  final url = pendingUrl ?? kPublicCheckInBaseUrl;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
