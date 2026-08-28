# DOT Excel reports — ATMOS field audit

**Date:** 2026-06-02  
**Scope:** What the app collects today vs what **Form A (DAE-3)**, **DAE 3B.2**, and **Part II** need.  
**Legend:** ✅ Yes · ⚠️ Partial · ❌ Missing · N/A Not applicable

---

## Summary

| Area | Ready for DOT Excel? |
|------|----------------------|
| Form A — country × month | ❌ No taxonomy mapping; ❌ no `.xlsx`; check-ins ≠ accommodation guests |
| DAE 3B.2 — PH origin × month | ⚠️ Province/city at signup only; ❌ no PSA region; ❌ no overnight flag |
| Part II — nights, sex | ⚠️ Sex at signup; ❌ guest nights / length of stay |
| Form A Part II — occupancy | ❌ Only static `roomCount` per establishment; no monthly occupancy |

**Bottom line:** ATMOS is strong for **QR attraction check-ins + tourist profile**. DOT annex forms need **extra fields**, **mapping tables**, and **Excel export** — not yet built.

---

## Phase 1 — Per visit / per guest

| # | Field | DOT need | ATMOS status | Where / notes |
|---|--------|----------|--------------|----------------|
| 1 | Visit / arrival **date** (→ month) | Required | ✅ | `qr_checkins.timestamp` (`lib/services/qr_checkin_service.dart`) |
| 2 | **Reporting municipality** | Required | ✅ | `municipalityId`, `municipality` on each check-in |
| 3 | **Overnight** vs day trip | Required | ❌ | Not collected at signup or check-in |
| 4 | **Domestic** vs foreign | Required | ⚠️ | `isLocal`, `localOrForeign` from signup (`country == Philippines`); not re-asked per visit |
| 5 | **Country of residence** | Form A | ⚠️ | Stored as `country`; UI label "Country of residence" for Filipinos (`signup_screen.dart`). Same field as home country — not a separate DOT field |
| 6 | **Nationality** | Form A PH section | ✅ | `nationality` on `tourists` (limited list + Other) |
| 7 | **Sex** (M/F) | 3B.2 Part II | ✅ | `sex`: Male / Female only (`_sexOptions`) |
| 8 | **PSA region** of origin | 3B.2 | ❌ | No `region` field; not derived from city |
| 9 | **Province** of origin | 3B.2 | ⚠️ | `province` — dropdown is **7 Mindanao provinces + Other**, not full PH (`_provinces`) |
| 10 | **City / municipality** of origin | 3B.2 | ⚠️ | `city` — full list only if province = **Misamis Occidental**; else "Select province first" |
| 11 | **Country** → Form A row | Form A | ⚠️ | `country` is free-text dropdown (~200 countries), **no** DOT row mapping (ASEAN sub-rows, etc.) |
| 12 | **Overseas Filipino** | Form A | ⚠️ | `Filipino (dual citizen)` nationality only; no explicit overseas-Filipino row flag |
| 13 | **Nights stayed** | Part II | ❌ | Not collected |
| 14 | **Guest / party count** per event | Optional | ⚠️ | `partyHeadcount`, `accompanyingChildrenCount` at **signup only** — not on check-in |
| 15 | **Unique visitor ID** | Audit | ✅ | Firebase `uid` / `tourist_id` on check-ins |
| 16 | **Establishment** link | Form A Part II | ⚠️ | Check-in links to **tourist spot** (`spot_id`), not `accommodation_establishments` |
| 17 | **Status** (verified / void) | QA | ⚠️ | UI treats `qr_checkins` as verified by default; no explicit workflow |

---

## Phase 2 — Accommodation (Form A Part II)

| # | Field | ATMOS status | Where / notes |
|---|--------|--------------|----------------|
| 18 | Rooms occupied (monthly) | ❌ | — |
| 19 | Rooms available (monthly) | ❌ | — |
| 20 | Guest-nights (monthly) | ❌ | — |
| 21 | Avg occupancy / length of stay | ❌ | — |
| 22 | Establishment registry | ⚠️ | `accommodation_establishments`: `name`, `type`, `roomCount`, `status`, `municipalityId` — **inventory only**, no monthly stats |
| 23 | Quarterly Q1–Q4 totals | ❌ | — |

---

## Phase 3 — Excel output

| # | Requirement | ATMOS status |
|---|-------------|--------------|
| 24 | Official Form A layout | ❌ |
| 25 | Official DAE 3B.2 layout | ❌ |
| 26 | Part II indicators section | ❌ |
| 27 | `.xlsx` with formulas / colors | ❌ — text report + CSV only (`tourism_dashboard.dart` `_generateReport`) |
| 28 | Prior year column (2023 vs 2024) | ❌ |

---

## Phase 4 — Mapping tables

| # | Table | ATMOS status |
|---|--------|--------------|
| 29 | Country → Form A row | ❌ |
| 30 | PH city → region + template row | ❌ |
| 31 | City name aliases (Ozamiz/Ozamis) | ⚠️ | `municipality_helper.dart` for **destination** LGUs only, not tourist origin |
| 32 | Unknown / unmapped bucket | ❌ |

---

## Phase 5 — Business rules (current behavior)

| Rule | ATMOS today |
|------|-------------|
| Same person, same spot, same day | **Still creates** new `qr_checkins` doc; welcome message notes repeat visit (`_priorScanState`) |
| Same person, different spots same day | **Multiple** check-ins counted |
| `totalVisits` on profile | Increments **once per location ever**, not per check-in |
| Who appears in LGU tourist list | Tourists with check-ins in municipality + `registrationMunicipalityId` (`tourism_dashboard.dart`) |
| Export joins profile to check-in | **No** — CSV is check-in only; tourist export is separate |

---

## Phase 6 — Signup / profile (detailed)

| Field | Firestore key | Status | Notes |
|--------|---------------|--------|-------|
| Sex | `sex` | ✅ | Male, Female |
| Nationality | `nationality` | ✅ | ~20 labels + Other; maps some to home country |
| Country of residence | `country` | ✅ | Large country list |
| Province | `province` | ⚠️ | Limited provinces; intl → `foreignRegion` saved as province |
| City | `city` | ⚠️ | MO cities + foreign city text |
| Barangay | `barangay` | ✅ | MO barangays via `misamis_occidental_barangays.dart` |
| Local / foreign | `isLocal`, `localOrForeign` | ⚠️ | Derived from Philippines residence, not DOT overnight rules |
| Date of birth | `dateOfBirth` | ✅ | Age analytics on governor dashboard |
| Party size | `partyHeadcount` | ⚠️ | Signup only |
| Prior destinations / how heard | `travelHistory` | ✅ | **Not** used in DOT forms |
| Transportation | `transportation` | ✅ | Not mapped to DOT |

---

## Phase 7 — Check-in record (`qr_checkins`)

| Field | Status |
|--------|--------|
| `timestamp` | ✅ |
| `userId` / `tourist_id` | ✅ |
| `municipalityId`, `municipality` | ✅ |
| `spotId`, `spot_name` | ✅ |
| `touristName` | ✅ |
| Nationality, country, sex, province, city | ❌ **Not denormalized** — must join `tourists/{uid}` |
| Overnight, nights | ❌ |

**CSV export columns today:** `Timestamp, Spot ID, Spot Name, User ID, Municipality, Municipality ID` — no demographic columns.

---

## Phase 8 — Reports UI (LGU tourism dashboard)

| Feature | Status |
|---------|--------|
| Daily / weekly / monthly / annual presets | ✅ Date filters only |
| DOT-named report types | ⚠️ "DOT Visitor to Attraction" & "DOT Accommodation Establishment Data" are **custom summaries**, not annex templates |
| Paste into Excel | ⚠️ Manual copy CSV |
| Dummy data seeder | ✅ `seedTourismDummyData` Cloud Function (test tourists + check-ins + accommodations) |

---

## Recommended build order (for dev)

1. **DOT confirmation** — QR check-in counts vs hotel overnight (policy).
2. **Per check-in (or per stay):** `isOvernight`, `nightsStayed` (if overnight).
3. **Full PH address** — all provinces + cities, or single searchable PSGC picker.
4. **`ph_region` + `dot_form_a_country_row`** — mapping tables (JSON in repo).
5. **Report job:** aggregate `qr_checkins` ⋈ `tourists` by year, month, municipality, dimension.
6. **Template fill:** official `.xlsx` (Cloud Function or admin-panel).
7. **Accommodation module:** monthly rooms occupied / guest-nights per establishment (if Form A Part II required).

---

## System-based report plan (ATMOS only)

**Principle:** Gamiton lang ang naa na. Ayaw sukad sa DOT annex layout hangtod naa mo’y bag-ong fields ug template.

### Data you already have

| Source | Fields useful for reports |
|--------|---------------------------|
| **`qr_checkins`** | `timestamp`, `userId`, `municipalityId`, `spotId`, `spot_name`, `municipality` |
| **`tourists`** (join by `userId`) | `sex`, `nationality`, `country`, `province`, `city`, `isLocal`, `localOrForeign`, `partyHeadcount`, `dateOfBirth`, `travelHistory`, `totalVisits` |
| **`accommodation_establishments`** | `name`, `type`, `roomCount`, `status` (static; no monthly stats) |
| **`tourist_spots`** | `name`, `category`, `municipalityId` |

Dashboard already **joins** check-ins to profiles for UI (`_enrichCheckInWithTouristProfile`); exports are still **separate CSVs**.

### Reports you can produce today (no code change)

Use **LGU Tourism Dashboard → Reports** + copy CSV to Excel.

| Report | How (existing UI) | Dimensions |
|--------|-------------------|------------|
| **Visits by month** | Custom/Annual report + check-in list; or check-in CSV → Excel pivot | Month × count |
| **Visits by spot** | `DOT Visitor to Attraction Report` type | Spot × visits, unique users |
| **Visitor registry** | Visitors tab → Export CSV | Per tourist: nationality, Local/Foreign, origin string, visits |
| **Check-in log** | Report preview → check-in CSV | Timestamp, spot, user id, municipality |
| **Accommodation inventory** | `DOT Accommodation Establishment Data` | Establishment count, room totals (not occupancy) |

**Manual Excel (2 files):** Export check-ins CSV + tourists CSV → `VLOOKUP` / Power Query on `User ID` = `tourist` uid → pivot:

- Rows: `nationality` or `country` or `Origin` (city, province, country string)
- Columns: month from `Timestamp`
- Values: count of check-ins (or distinct `User ID`)

### Reports that match your system semantics (not DOT annex)

| Label | Definition in ATMOS |
|-------|---------------------|
| **“Guest arrival”** | One row in `qr_checkins` (each QR scan creates a doc; same user can scan again same day) |
| **“Domestic”** | `isLocal == true` or `localOrForeign == 'Local'` (Philippines as country of residence at signup) |
| **“Foreign”** | Opposite of above |
| **“Origin”** | `city, province, country` joined as text — **not** PSA region rows |
| **“Overnight”** | **Not defined** — treat all QR check-ins as same category or don’t report overnight |

### Suggested “ATMOS standard exports” (if you extend the app later)

Build these from `qr_checkins` ⋈ `tourists` only — no new signup questions:

1. **Monthly check-ins by nationality** (columns: Jan–Dec or single period columns)
2. **Monthly check-ins by country** (`country` field)
3. **Monthly check-ins by origin city** (`city` — raw strings, accept duplicates like “Ozamiz” vs “Ozamiz City”)
4. **Monthly check-ins by sex** (from profile; skip if profile missing)
5. **Monthly check-ins by Local vs Foreign**
6. **Monthly check-ins by spot** (already close to DOT Visitor to Attraction)
7. **Registered tourists vs active scanners** (tourists with ≥1 check-in in period)

Optional columns in one **wide check-in CSV** (dashboard already has join logic):  
`Timestamp, User ID, Spot, Municipality, Sex, Nationality, Country, Province, City, Local/Foreign, Party headcount (signup)`

### Do not promise from current system

- Official **Form A / DAE 3B.2** `.xlsx` with continent/country rows
- **Overnight domestic** breakdown by NCR/CAR regions
- **Guest nights**, **length of stay**, **rooms occupied** per month
- **Prior-year % difference** (no 2023 store)
- Exact DOT **grand total** = hotel guests (you measure **attraction QR visits**)

### One-line LGU message

> “Ang ATMOS report karon = **QR check-in analytics** with **visitor profile** (nationality, origin, sex, local/foreign). Dili pa automatic ang DOT annex Excel; pwede i-pivot sa Excel gikan sa exported CSV.”

---

## Files referenced

- Signup / profile: `lib/screens/signup_screen.dart`
- Check-in: `lib/services/qr_checkin_service.dart`
- LGU reports: `lib/screens/tourism_dashboard.dart`
- Accommodations seed: `functions/index.js` (`accommodation_establishments`)
- Barangays (MO only): `lib/data/misamis_occidental_barangays.dart`
