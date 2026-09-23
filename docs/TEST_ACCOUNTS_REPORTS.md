# Test accounts for report generation

Use these **demo accounts only** in Firebase projects you control.

## Dashboard analytics (visible on LGU / Governor charts)

Real QR scanning is slow for demos. Seed **dashboard-visible** check-ins that
also appear under **Registered Tourists**:

### In the app (recommended)

1. Log in as LGU tourism (e.g. Oroquieta).
2. **Settings → Debug data → Seed tourist data**
   - Choose municipality or “Seed all municipalities”
   - Set Filipino / Foreign counts (e.g. 3 Filipino + 7 foreign)
   - Optionally pick tourist spots
3. **Settings → Debug data → Clear tourist database**
   - Type `CLEAR ALL TOURISTS` to confirm
   - Toggle “Only this LGU” off to wipe the whole tourist database

Requires deployed functions (Blaze), **or** the app falls back to direct Firestore
writes after rules publish:

```bash
firebase deploy --only firestore:rules
firebase deploy --only functions:seedLguAnalyticsData,functions:clearAllTouristData
```

### CLI

```bash
# Requires: deployed seedLguAnalyticsData
node tools/seed_dashboard_analytics.js oroquieta 14 6
node tools/seed_dashboard_analytics.js oroquieta 10 5 --all
```

These rows use:
- UID prefix `seed_tourist_…`
- email `@misocc-seed.ph`
- `source: qr_scan` + `seedTag: lgu_analytics_debug_v1`
- `registrationMunicipalityId` so **Registered Tourists** lists them

Cleanup: app **Clear tourist database**, or `node tools/cleanup_beta_firestore.js --apply`

## Monthly report testing (quick start)

1. Deploy functions: `firebase deploy --only functions:seedTourismDummyData`
2. Log in as LGU tourism → **Settings → Seed tourist data** (or use CLI above)
3. For classic monthly CSV seed, use:

| Email | Password |
|-------|----------|
| **`monthly.reports@misocc-demo.ph`** | **`ATMOS#Monthly@2026`** |

4. **Reports → Monthly Report → Export → Preview → Download summary CSV**

> Note: the classic `dummy_tourist_*` / `@dummy-tourist.test` seed is filtered out of live dashboard KPIs. Use **Settings → Seed tourist data** (or `seed_dashboard_analytics.js`) for charts.

## All demo logins (after classic seed)

| Role | Email | Password |
|------|--------|----------|
| **Monthly reports** | `monthly.reports@misocc-demo.ph` | `ATMOS#Monthly@2026` |
| General reports | `reports.demo@misocc-demo.ph` | `ATMOS#Reports@2026` |
| LGU tourism | `tourism.jimenez@misocc-demo.ph` | `ATMOS#Tourism@2026_MisOcc!` |
| Provincial tourism | `tourismoffice.atmos@misocc-demo.ph` | `ATMOS#Tourism@2026_MisOcc!` |
| Governor | `governor.atmos@misocc-demo.ph` | `Asenso@MISocc#2026!Gov` |

Replace `jimenez` with your municipality id when seeding.

## Seed from terminal

```bash
# Dashboard KPIs / charts + Registered Tourists (visible)
node tools/seed_dashboard_analytics.js oroquieta 14 6

# Monthly CSV only (filtered on dashboards)
node tools/seed_dummy_data.js jimenez monthly

# All (monthly + annual Jan–Mar)
node tools/seed_dummy_data.js jimenez all
```

## What gets seeded

### `seedLguAnalyticsData` (Settings / seed_dashboard_analytics.js)
- Custom Filipino / Foreign counts + optional spot filter
- Multi-day `qr_checkins` with partySize / gender
- Appears on LGU Registered Tourists + Analytics / DOT / OPTACA
- Tagged `lgu_analytics_debug_v1`

### `reportFocus: monthly` (classic dummy)
- 12 dummy visitors with sex, nationality, origin
- 2–4 check-ins each in **current calendar month** on varied days
- Spots, accommodations, demo Auth users

### `reportFocus: all` (default classic)
- Everything above **plus** Jan–Mar check-ins for annual reports
- 15 dummy visitors

## Troubleshooting

| Issue | Fix |
|--------|-----|
| `functions/not-found` | Deploy Cloud Functions first |
| `failed-precondition` (classic seed) | Set `ALLOW_DUMMY_SEED=true` on Functions env |
| Monthly report empty | Re-run monthly seed; confirm logged-in user's `municipalityId` matches seed |
| Dashboard KPIs still 0 | Use Settings seed or `seed_dashboard_analytics.js` (not classic dummy seed) |
| Wrong month columns | Monthly report uses day 1 → today of current month |
| Clear requires phrase | Type exactly `CLEAR ALL TOURISTS` |
