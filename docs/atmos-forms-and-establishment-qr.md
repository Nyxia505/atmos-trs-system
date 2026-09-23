# Atmos TRS — Forms + establishment QR (locked agreements)

**Status:** Product decisions locked. Establishment stay QR flow is implemented in app code (deploy `firestore.rules` for client writes).  
**Related code:** `lib/config/supabase_report_templates_config.dart`, `lib/utils/dot_report_*`, `lib/widgets/dot_report_export_panel.dart`, `lib/services/establishment_stay_service.dart`, `lib/screens/establishment_dashboard_screen.dart`.

---

## 1. DOT / Analytics forms

### Goal

Automate the manual DOT/DAE/MICE fill flow. LGU Analytics is not a blank-template library.

### Rules

1. **Every form** in the catalog gets a **full preview** of what will be exported.
2. Preview/export use **best effort** from data available at that time (check-ins ⋈ profiles; later confirmed establishment stays).
3. Missing cells are **gaps** (preview note + `ATMOS_GAPS` in Excel) — not “download blank” as the primary action.
4. Primary actions: **Download Excel** and **Download PDF** (same content as preview).
5. Official empty template download is **advanced/secondary** only.
6. One pipeline: **aggregate → preview → Excel → PDF**. New fields update fillers; do not add parallel exporters.
7. When signup/check-in/stay fields expand, previews and downloads update automatically via the same pipeline.

### Data routing

| Source | Forms |
|--------|--------|
| Attraction / LGU QR visits | VAR family (VAR 2, 4, 5, …) |
| Confirmed establishment stays | DAE family (DAE-3, 3B.2, Form A, 1B, 1A, …) |
| Events (future / LGU events) | MICE / CUS |

If DAE is filled from attraction check-ins as a temporary proxy, label it clearly as a **gap/proxy** until confirmed establishment stays exist in the date range.

### Completeness grows over time

| Phase | What fills |
|-------|------------|
| Now | Profiles + QR check-ins (VAR); **confirmed AE stays** → DAE-3 / 3B.2 / Form A / AE-gap forms |
| Mapping tables | PSA region, DOT country taxonomy rows |
| AE inventory | Total rooms available per month (from `roomCount` + future inventory) |
| Later | MICE utilization from event flows |

### DAE wiring (implemented)

- Query: `fetchConfirmedEstablishmentStays` (`lib/utils/establishment_stay_report_query.dart`) — **status == confirmed or checked_out**.
- Aggregates: `aggregateDae3FromConfirmedStays` / `aggregateDae3PreferringStays` in `dae3_aggregates.dart`.
- Preview + Excel + PDF: LGU Analytics `DotReportExportPanel` loads confirmed stays for accommodation forms; guest nights = partySize × nights; rooms from staff confirm.
- Pending stays never count.

### OPTACA establishment approval

Provincial Tourism → **Establishments** tab → approve/reject `accommodation_establishments` + matching `users` status. Active AEs can confirm stays that feed DAE.

### LGU establishment inventory (view only)

LGU municipal tourism → **Establishments** tab → establishments **in that municipality only** (e.g. Oroquieta sees Oroquieta AEs). No approve/reject — OPTACA owns approval. Used as local inventory alongside Tourist Spots; confirmed stays already scope into LGU Analytics DAE forms by municipality.

---

## 2. Establishment (hotel / AE) QR flow

### Locked decisions

1. **Tourist scans** the establishment QR → creates a **pending** stay request (not counted in DOT yet).
2. **Hotel staff** (logged into establishment dashboard) get a **queue / popup**, enter required fields, then **confirm**.
3. After confirm, the stay **reflects on the tourist side** as **history / receipt** for that transaction (what was included).
4. **Same calendar day:** one person may have both an **attraction check-in** and a **hotel stay** as **separate records**.

### Status machine

`pending` → `confirmed` (or `rejected`) → `checked_out` (after guest leaves)

- Tourist while pending: “Waiting for front desk…”
- Explicit **check-out** frees rooms; tourist leaves hotel + room review (`establishment_stay_reviews`).
- DOT / LGU DAE aggregates: **confirmed** and **checked_out** (not pending / rejected)

Lodging AEs store profile `checkInTime` / `checkOutTime`. Desk confirm before check-in time defaults an extra night (early arrival). Planned `checkOutAt` uses the AE check-out clock.

### Suggested record shape (implement when building)

Collection idea: `establishment_stay_requests` (name may vary; keep one clear collection).

Minimum fields:

- `establishmentId`, `touristId`, `municipalityId`
- `status`: `pending` | `confirmed` | `rejected` | `checked_out`
- `createdAt`, `confirmedAt`, `confirmedByStaffUid`, `checkedOutAt`
- Staff-entered: `nightsStayed`, `roomsOccupied`, `checkInAt`, `checkOutAt`, party summary, notes
- Receipt mirror for tourist history (same doc or tourist-subcollection copy)

Mechanics: tourist scan writes pending → establishment app **listens** (and/or FCM) → staff confirms → tourist listener updates receipt → checkout + review. Cross-device; not a local-only popup on the tourist phone.

### Do not

- Count pending stays in official reports.
- Overload attraction `qr_checkins` without explicit `qr_type` / `establishmentId`.
- Require rebuilding DOT exporters when stay fields are added — only extend aggregators.

---

## 3. OPTACA (related)

LGU submit packages should eventually attach the same generated Excel/PDF. Until that slice lands, packages may remain metrics/notes only — extend `lgu_report_submission_service`, do not invent a second inbox.

---

## 4. One-line policy

> Attraction QR feeds VAR; establishment QR (staff-confirmed) feeds DAE; Analytics always shows best-fill preview with gaps; primary downloads are Excel + PDF — never blank official as the happy path.
