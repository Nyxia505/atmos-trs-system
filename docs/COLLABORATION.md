# ATMOS TRS collaboration

One GitHub repository holds both modules. `linontripplanner-main` is a normal folder in this repo, wired in as the Flutter package `trip_plan` (`pubspec.yaml` path dependency). It is not a Git submodule and it does not have its own `.git` folder. Commits in this repository are how Trip Planner changes are shared. Do not copy the folder between machines.

Remote: `https://github.com/Nyxia505/atmos-trs-system.git`  
Stable branch: `main`  
Web hosting: Firebase Hosting project `atmos-trs-system`, site files from `build/web` (`firebase.json`).

## Branches

| Branch | Who | What to change |
| --- | --- | --- |
| `main` | Reviewed merges only | Integrated app. Do not develop directly here. |
| `feature/atmos-trs` | ATMOS TRS / VR Tour developer | VR Tour, LGU, reports, and ATMOS screens outside Trip Planner. |
| `feature/trip-planner` | Trip Planner developer | `linontripplanner-main/` |

Shared files need a review from the other developer before merge:

- `lib/screens/landing_page.dart`
- `lib/screens/login_screen.dart`, `lib/screens/signup_screen.dart`
- `lib/navigation/`
- `lib/services/startup_route_resolver.dart`
- `lib/services/camera_qr_deep_link_service.dart`
- `pubspec.yaml`
- `firebase.json`, `.firebaserc`

Leave landing design, QR navigation, shared tourist auth, the APK download section, destination cards, logos, fonts, and Firebase project config as they are unless the pull request explains the shared change.

## Developer A — ATMOS TRS

```bash
git checkout main
git pull origin main
git checkout -B feature/atmos-trs
# edit ATMOS TRS files
git add -A
git commit -m "Describe the ATMOS TRS change"
git push -u origin feature/atmos-trs
```

Open a pull request from `feature/atmos-trs` into `main`. GitHub Actions runs `flutter pub get`, `flutter analyze`, and `flutter test`. Merge only after the checks pass and the other developer has reviewed shared files.

## Developer B — Trip Planner

```bash
git checkout main
git pull origin main
git checkout -B feature/trip-planner
# edit linontripplanner-main/
git add linontripplanner-main
git commit -m "Describe the Trip Planner change"
git push -u origin feature/trip-planner
```

Open a pull request from `feature/trip-planner` into `main`. The same checks run. Trip Planner stays a path package, so the landing page and ATMOS auth keep using it after the merge. No folder copy step.

## Review and merge

1. Push the feature branch. That starts validation. It does not deploy the website.
2. Open a pull request into `main`.
3. Wait for the **Validate** workflow to pass. A failing analysis error or test blocks the merge. Existing infos and warnings do not fail the check.
4. Review the diff. Do not merge conflicts or failing checks.
5. Merge the pull request into `main` (merge commit or squash). GitHub does not auto-merge.

## What happens after merge

A push to `main` runs **Deploy web**:

1. `flutter pub get`
2. `flutter build web --release`
3. Firebase Hosting deploy to project `atmos-trs-system` (live channel)

The landing page updates from that web build. Phones that already installed an APK do not update from this deploy.

Confirm success: GitHub → Actions → **Deploy web** → green check. Then open the Firebase Hosting URL for `atmos-trs-system`.

### Required secret (not created by this repo)

In the GitHub repo settings, add a secret named `FIREBASE_SERVICE_ACCOUNT_ATMOS_TRS`. Its value is the JSON key for a Google service account that can deploy Hosting to `atmos-trs-system`. Do not commit that JSON file.

This workflow file does not deploy anything until it is on `main` and that secret exists. Confirm before the first production deploy.

Recommended branch protection on `main` (apply in GitHub after you confirm; it is not set from this repository):

- Require a pull request before merging
- Require the **Validate** check to pass
- Do not allow force pushes

## Merge conflicts

```bash
git checkout feature/trip-planner
git fetch origin
git merge origin/main
# fix the marked files, then
git add -A
git commit
git push
```

Use the same steps on `feature/atmos-trs`. If both people edited `landing_page.dart` or `pubspec.yaml`, keep both module behaviors and ask the other developer to review that file.

## Android APKs

Updating the website does not update installed apps.

**Build Android APKs** is manual (Actions → Run workflow). It does not publish to the landing page.

| Choice | Output | Package id |
| --- | --- | --- |
| `atmos-trs` | `app-release.apk` from the root app | `com.atmos.trs` |
| `trip-planner` | `app-release.apk` from `linontripplanner-main` | `com.example.flutter_application_1` |

Download the artifact from the Actions run, host the file, then set the real URL in `lib/config/app_store_links.dart`:

- VR Tour: `kAndroidApkDownloadUrl` (already points at the GitHub release asset `atmos-trs.apk`)
- Trip Planner: `kTripPlannerApkDownloadUrl` (empty until a file is hosted)

Ship that URL change through a pull request so the landing page links the new file. The two APKs do not share a local login session. They can use the same Firebase accounts only if Trip Planner is built against the same Firebase project.

