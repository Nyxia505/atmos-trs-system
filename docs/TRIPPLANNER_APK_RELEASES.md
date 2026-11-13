# TripPlanner APK — GitHub Releases

Website download button always uses:

`https://github.com/Nyxia505/atmos-trs-system/releases/latest/download/tripplanner.apk`

Firebase Spark cannot host APKs. Do **not** commit APK binaries to git.

## Publish a new TripPlanner build

1. Bump `linontripplanner-main/pubspec.yaml` `version:` (e.g. `1.0.5+7`).
2. Create and push a tag, then a GitHub Release whose tag starts with `tripplanner-`:

```bash
git tag tripplanner-v1.0.5
git push origin tripplanner-v1.0.5
# --latest=false keeps the ATMOS TRS release as repo "Latest" so
# /releases/latest/download/atmostrs.apk keeps working.
gh release create tripplanner-v1.0.5 --title "TripPlanner v1.0.5" --notes "TripPlanner Android release" --latest=false
```

3. Workflow **TripPlanner Release APK** runs on that published release, builds the Flutter APK, uploads **`tripplanner.apk`** to that tag, and also clobbers the same asset on the current Latest release so the website URL always works.

## Manual rebuild onto an existing release

Actions → **TripPlanner Release APK** → Run workflow → set `release_tag` (e.g. `v1.0.9` or `tripplanner-v1.0.5`).

## Optional signing secrets

Current app `build.gradle.kts` signs release with the debug keystore (demo installs). For a production keystore, add repository secrets and wire them in the workflow later:

| Secret | Purpose |
|---|---|
| `KEYSTORE_BASE64` | Base64-encoded `.jks` / `.keystore` |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias |
| `KEY_PASSWORD` | Key password |

Never put tokens or keystore files in frontend / landing Dart code.

## Local upload (dev machine)

```powershell
cd linontripplanner-main
flutter build apk --release --target-platform android-arm64
Copy-Item build\app\outputs\flutter-apk\app-release.apk ..\.tools\tripplanner.apk -Force
gh release upload v1.0.9 ..\.tools\tripplanner.apk --clobber
```
