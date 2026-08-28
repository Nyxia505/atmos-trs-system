# ATMOS-TRS beta — Firestore cleanup

Run **once** before beta testing to remove seeded demo records.  
This keeps collection structure and official tourist spots; it only deletes test data.

## What gets removed

| Collection | Criteria |
|------------|----------|
| `tourists` | `firebaseUid` / doc id starts with `dummy_tourist_`, or email contains `@dummy-tourist.test`, or `source == dummy_seed` |
| `qr_checkins` | `source == dummy_seed`, or `userId` starts with `dummy_tourist_`, or tourist email `@dummy-tourist.test` |
| `users` | Demo-only accounts (optional — review list below before delete) |

## What to keep

- Administrator / governor / LGU staff accounts you need for beta
- `tourist_spots` canonical destination documents
- Real tourist registrations from beta testers
- Real `qr_checkins` from actual scans

## App-side filters

The Flutter app now excludes dummy seed rows via `lib/utils/production_data_filters.dart`:

- LGU dashboard (`tourism_dashboard.dart`)
- Governor dashboard (`governor_dashboard.dart`)

Dashboard cards show **0** when no real data exists.

## Disable dummy seeding

The Cloud Function `seedTourismDummyData` is blocked unless `ALLOW_DUMMY_SEED=true` in the Functions environment (dev only).

## Manual cleanup (Firebase Console)

1. Open [Firebase Console](https://console.firebase.google.com) → Firestore.
2. **qr_checkins**: Delete documents where `source` is `dummy_seed`.
3. **tourists**: Delete documents whose id starts with `dummy_tourist_` or email ends with `@dummy-tourist.test`.
4. **Authentication**: Remove test tourist Auth users you no longer need (keep staff accounts).

## Optional: Firebase CLI script

From project root (requires service account / `firebase login`):

```bash
node tools/cleanup_beta_firestore.js
```

Review `tools/cleanup_beta_firestore.js` before running in production.

## After cleanup

1. Hot restart / redeploy the Flutter app.
2. Sign in as LGU or Governor and confirm dashboards show 0 until real check-ins occur.
3. Run one real tourist registration + QR check-in to verify counts update.
