# Publish Firestore rules (fixes permission-denied)

The app reads `firestore.rules` in this folder. **Until you publish them in Firebase Console,** tourism dashboards and QR registration check-ins will show:

`[cloud_firestore/permission-denied] Missing or insufficient permissions.`

## Steps (about 2 minutes)

1. Open: https://console.firebase.google.com/project/atmos-trs-system/firestore/rules  
2. Select the **atmos-trs-system** project.  
3. Replace the entire rules editor with the contents of **`firestore.rules`** in this repo.  
4. Click **Publish**.  
5. Restart the app (fully close and reopen).

## Optional: Firebase CLI

```bash
npm install -g firebase-tools
firebase login
cd c:\atmos_trs_system
firebase deploy --only firestore:rules
```

## What the rules allow (after publish)

- `qr_checkins` — any signed-in user can read; tourists write their own scans
- `tourists` — any signed-in user can read (LGU dashboards); only the owner can create/update
- `vr_tours` — public read (view counts); signed-in write
- `users/{uid}/faq_chats` — tourists read/write their own FAQ chat history

- `tourismoffice.atmos@misocc-demo.ph`
- `tourism.oroquieta@…` (any domain)
- `governor.atmos@misocc-demo.ph`
- Any `users/{uid}` document with `role: tourism` or `tourism_office` and optional `municipalityId` (e.g. `oroquieta`)

Municipal LGU accounts also need `users/{uid}.municipalityId` set (the app writes this on login). After publishing rules, sign out and sign in again so the staff profile is refreshed.

## Tourist QR registration flow

1. Scan spot or LGU QR (guest — no account yet).  
2. Register and verify email.  
3. The app auto-saves the check-in to `qr_checkins` (no second scan needed).  
4. Tourism dashboard **Visit log** reads `qr_checkins` filtered by your municipality (`oroquieta` during beta).  
5. **Publish rules** (step above) — `qr_checkins` must allow read for signed-in users.
