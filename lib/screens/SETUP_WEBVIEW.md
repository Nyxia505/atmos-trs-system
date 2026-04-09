# VR tour & webview_flutter setup notes

- **Android/iOS**: VR tours open in-app via **WebView** ([VRWebViewScreen], [webview_flutter]).
- **Web**: VR tours open in the browser in a **new tab** via [url_launcher] (no WebView on web).
- Use the helper **openVrTour(context, {url?, title})** so the correct behavior is chosen per platform.

## 1. Dependencies

In `pubspec.yaml`:

```yaml
dependencies:
  webview_flutter: ^4.4.2
  webview_flutter_android: ^3.14.0
  webview_flutter_wkwebview: ^3.9.0
  url_launcher: ^6.2.4
```

Run: `flutter pub get`

## 2. Android

- **minSdkVersion**: 19 or higher in `android/app/build.gradle` (default Flutter template is usually 21+).
- If you see WebView rendering issues with Impeller, you can disable it for the app via `AndroidManifest.xml` (optional):
  - Inside `<application>` add:
    ```xml
    <meta-data
      android:name="io.flutter.embedding.android.EnableImpeller"
      android:value="false" />
    ```

## 3. iOS

- iOS 11+ supported by default.
- For **HTTPS** URLs (like project-title-2.tiiny.site) no extra config is needed.
- If you need to load **HTTP** (insecure) URLs, add in `ios/Runner/Info.plist`:
  - `NSAppTransportSecurity` → `NSAllowsArbitraryLoads` = `true` (or allow specific domains only).

## 4. Usage

**Recommended:** use the helper so Android/iOS get in-app WebView and Web gets a new tab.

**Bundled 360° VR tour (Marzipano, Oroquieta City Plaza):**

```dart
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';

// Opens the in-app VR tour (multi-scene, hotspots) from assets/vr_tour/
openVrTour(context, useLocalTour: true, title: 'Oroquieta City Plaza');
```

**External URL:**

```dart
openVrTour(context, url: 'https://project-title-2.tiiny.site/', title: 'VR Tour');
```

To push the WebView screen directly (Android/iOS only; do not use on Web):

```dart
// Bundled tour
Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => VRWebViewScreen(
      title: 'Oroquieta City Plaza',
      useLocalTour: true,
    ),
  ),
);

// Or with URL
Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => VRWebViewScreen(
      title: 'Sapang Dalaga Falls',
      initialUrl: 'https://project-title-2.tiiny.site/',
    ),
  ),
);
```
