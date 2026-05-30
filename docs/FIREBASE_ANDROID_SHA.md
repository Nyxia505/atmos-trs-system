# Firebase Android — fix “Requests from this Android client … are blocked”

That error means Google does not recognize your **`com.atmos.trs`** build certificate yet. Fix it in **Firebase Console** (and optionally **Google Cloud Console**).

## 1. Add fingerprints in Firebase

1. Open [Firebase Console](https://console.firebase.google.com/) → project **atmos-trs-system**.
2. Project **Settings** (gear) → **Your apps** → select the Android app **`com.atmos.trs`** (not `com.example...`).
3. Under **SHA certificate fingerprints**, click **Add fingerprint** and add:
   - **SHA-1** (required for many Auth flows)
   - **SHA-256** (recommended)
4. Use the debug keystore for local development:

   ```powershell
   keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" `
     -alias androiddebugkey -storepass android -keypass android
   ```

   Copy the **SHA1** and **SHA-256** lines from the output.

5. **Release builds:** Add the SHA-1/SHA-256 of your **upload** keystore / Play App Signing certificate as well, or Play Store installs will hit the same error.

6. After saving, wait **a few minutes** for Google to propagate.

## 2. Refresh `google-services.json`

`oauth_client` should **not** stay empty for your main app after fingerprints exist.

1. Firebase → Project settings → Android `com.atmos.trs` → **Download google-services.json**.
2. Replace `android/app/google-services.json` in this repo with the new file.
3. Rebuild the app (`flutter clean` optional, then `flutter run`).

## 3. If it still fails: API key restrictions

Your keys (see `google-services.json` → `api_key` → `current_key`):

1. [Google Cloud Console](https://console.cloud.google.com/) → same project **atmos-trs-system** → **APIs & Services** → **Credentials**.
2. Open each **API key** used by Firebase (match the keys in `google-services.json`).
3. Under **Application restrictions**:
   - Either choose **Android apps** → add package **`com.atmos.trs`** + the **same SHA-1**,  
   - Or temporarily **None** while testing.

## Reference

Package name: **`com.atmos.trs`** (must match `android/app/build.gradle.kts`).
