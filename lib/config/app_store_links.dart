// Public store / download URLs for the ATMOS TRS mobile app.
// Replace placeholders when listings and APK hosting are live.

const String kGooglePlayStoreAppUrl =
    'https://play.google.com/store/apps/details?id=com.atmos.trs';

const String kAppStoreAppUrl =
    'https://apps.apple.com/app/id0000000000';

/// Direct Android APK download (Firebase Hosting, GitHub Releases, etc.).
/// Leave empty to hide the APK button until a file is hosted.
const String kAndroidApkDownloadUrl =
    'https://atmos-trs-system.web.app/downloads/atmos-trs.apk';

bool get kHasAndroidApkDownload => kAndroidApkDownloadUrl.trim().isNotEmpty;
