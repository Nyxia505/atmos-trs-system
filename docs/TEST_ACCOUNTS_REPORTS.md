# Test accounts for report generation

Use these **demo accounts only** in Firebase projects you control.

## Monthly report testing (quick start)

1. Deploy functions: `firebase deploy --only functions:seedTourismDummyData`
2. Log in as governor/tourism staff → **Settings → Populate monthly report test data** → Generate
3. Log out → log in:

| Email | Password |
|-------|----------|
| **`monthly.reports@misocc-demo.ph`** | **`ATMOS#Monthly@2026`** |

4. **Reports → Monthly Report → Export → Preview → Download summary CSV**

Check-ins are seeded on **multiple days in the current month** (days 1, 3, 5, 8, … through today) so the monthly matrix has data in several day columns.

## All demo logins (after seed)

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
# Monthly only
node tools/seed_dummy_data.js jimenez monthly

# All (monthly + annual Jan–Mar)
node tools/seed_dummy_data.js jimenez all
```

## What gets seeded

### `reportFocus: monthly`
- 12 dummy visitors with sex, nationality, origin
- 2–4 check-ins each in **current calendar month** on varied days
- Spots, accommodations, demo Auth users

### `reportFocus: all` (default)
- Everything above **plus** Jan–Mar check-ins for annual reports
- 15 dummy visitors

## Troubleshooting

| Issue | Fix |
|--------|-----|
| `functions/not-found` | Deploy Cloud Functions first |
| Monthly report empty | Re-run monthly seed; confirm logged-in user's `municipalityId` matches seed |
| Wrong month columns | Monthly report uses day 1 → today of current month |
