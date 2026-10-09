# Atmos TRS — Forms + establishment DOT register (locked agreements)

**Status:** Product decisions locked. The establishment QR stay flow and establishment reviews are **retired**; hotels enter a monthly DOT register (DAE-1B) instead (deploy `firestore.rules` for client writes).  
**Related code:** `lib/config/supabase_report_templates_config.dart`, `lib/utils/dot_report_*`, `lib/widgets/dot_report_export_panel.dart`, `lib/services/ae_register_service.dart`, `lib/utils/ae_register_calculator.dart`, `lib/utils/ae_register_report_query.dart`, `lib/widgets/ae_register/`, `lib/screens/establishment_dashboard_screen.dart`.

---

## 1. DOT / Analytics forms

### Goal

Automate the manual DOT/DAE/MICE fill flow. LGU Analytics is not a blank-template library.

### Rules

1. **Every form** in the catalog gets a **full preview** of what will be exported.
2. Preview/export use **best effort** from data available at that time (check-ins ⋈ profiles for VAR; hotel DOT registers for DAE).
3. Missing cells are **gaps** (preview note + `ATMOS_GAPS` in Excel) — not “download blank” as the primary action.
4. Primary actions: **Download Excel** and **Download PDF** (same content as preview).
5. Official empty template download is **advanced/secondary** only.
6. One pipeline: **aggregate → preview → Excel → PDF**. New fields update fillers; do not add parallel exporters.
7. When signup/check-in/register fields expand, previews and downloads update automatically via the same pipeline.

### Data routing

| Source | Forms |
|--------|--------|
| Attraction / LGU QR visits | VAR family (VAR 2, 4, 5, …) |
| Hotel DOT registers (`ae_monthly_reports`) | DAE family (DAE-3, 3B.2, Form A, 1B, 1B.2, 1A, …) |
| Venue MICE event logs (`mice_monthly_reports`) | CUS MICE (CUS SUMMARY + CUS BY EST) — see §2b |

If DAE is filled from attraction check-ins as a temporary proxy, label it clearly as a **gap/proxy** until hotel register months exist in the date range.

### DAE wiring (implemented)

- Query: `fetchAeRegisterReportData` (`lib/utils/ae_register_report_query.dart`) — AE-month headers with at least one row or a “no guests” day. DAE forms are **monthly**: a date range selects every month it overlaps (gap note when the range is partial).
- Scope: one establishment (`aeId`) › LGU (`municipalityId`) › province-wide.
- Drafts (not yet submitted) **are included**, with a gap note; demo-seeded months are flagged too.
- Fillers (`dot_report_preview.dart`, `dot_report_export_service.dart`):
  - **DAE-3** — `aggregateDae3FromAeReports`: guests = check-ins, guest-nights = Σ register guests, rooms occupied = register rows, rooms available = AE total rooms.
  - **DAE3 Form A / DAE 1B.2** — DAE-1B “by Country (Sum)” matrix (`AeRegisterCalculator.countryMatrix`).
  - **DAE 3B.2 / DAE 1B.2 Dom** — domestic arrivals by PH region × month (unfilled region → “Region not specified”).
  - **DAE-1B** — DAE-2 summary for one AE-month; KPI line per AE-month otherwise.
  - **DAE-1A** — daily MonthlyRecord tally (fetches rows).

### OPTACA establishment approval

Provincial Tourism → **Establishments** tab → approve/reject `accommodation_establishments` + matching `users` status. Active lodging AEs file their monthly register; OPTACA sees a province-wide **register compliance** table (submitted / draft / missing).

### LGU establishment inventory (view only)

LGU municipal tourism → **Establishments** tab → establishments **in that municipality only**, plus the register compliance table for the selected month. No approve/reject — OPTACA owns approval. “Open” shows the read-only register + Insights.

---

## 2. Establishment DOT register (DAE-1B)

Source workbook: `forms_format/1.-DOT_ET_DAE1Bv10c.xlsm`. Each sheet became an input / computed page on the establishment dashboard.

### Locked decisions

1. **Hotels type the data** after logging in — no tourist scanning, no staff confirm queue, no rooms tab.
2. **Daily Register** = one row per occupied **room-night**: date, room, residence (country / PH resident / overseas Filipino / unspecified), optional PH region, guests, female, male, checked-in day flag, room rate, optional Charges A/B. “Add stay” expands guests × nights into rows.
3. **Computed, never typed:** Monthly Record (per day), DAE-2 summary, By Country (Sum).
   - Occupancy = rooms occupied ÷ (rooms available × days)
   - ALOS = guest-nights ÷ guests checked-in
   - Guest-nights = guests × nights (Σ register guests)
4. Columns adapt to the establishment type via `AeRegisterSchema` (lodging first; the schema is extensible for other types later).
5. Hotel marks the month **submitted**; LGU / OPTACA / Governor read it. Rate and sales are visible to them; Charges A/B are optional hidden columns.
6. **Retired:** establishment QR stay requests (`establishment_stay_requests`), establishment reviews (`establishment_stay_reviews`). Old printed hotel QRs show a “retired” message. Legacy docs are staff-purge only.
7. **Sign-offs instead of extra logins:** one hotel login; every major save (add stay / single night, edit, delete, stays another night, mark / clear “no guests”, submit, back to draft, DOT reporting profile) asks **name + position (remembered per hotel) + a fresh signature every time** + certification checkbox. A reason is required for deletes, back-to-draft and any change to a submitted month. Cancelling the dialog saves nothing.

### Sign-offs (audit evidence)

- `signoffs/{id}` — append-only (rules deny update/delete). Fields: `subjectType` (`ae_register` · `mice_register` · `ae_profile`; add new constants in `SignOffSubjects` for future forms), `subjectId` (report id / AE uid), `ownerId`, `municipalityId`, `periodKey`, `action` + `actionLabel`, `summary`, `details`, `reason`, `signerName`, `signerPosition`, `signaturePng` (PNG blob) + `signatureSha256`, `contentHash`, `snapshot` (totals after the save), `changes` (before/after per row, max 60), `accountUid` / `accountEmail`, `platform`, `createdAt`.
- Register sign-offs commit **in the same batch** as the rows + header they certify. Rows carry `signOffId`, `encodedBy`, `encodedPosition`, `createdBy`, `createdAt`, `updatedAt`; the header carries `lastSignOff` (id, action, name, position, at, `contentHash`).
- **Changed after signing:** the workspace / viewer recompute the month hash (rows + `zeroDays`) and flag a mismatch with `lastSignOff.contentHash` (e.g. edits made outside the app).
- Remembered people: `signoff_signers/{aeId}/people/{key}` (owner only). Forgetting a person never touches past sign-offs.
- **DAE PDFs** (LGU / OPTACA / Governor export) print the latest sign-off per AE-month (signature, name, position, action, time) and list months with no signature on file.
- UI: `lib/widgets/sign_off/` (dialog, pad, history panel) · `SignOffService` · register “Sign-offs” tab · Profile tab history.

### Data shape

- Header `ae_monthly_reports/{aeId}_{yyyy}_{mm}`: AE identity (name, municipality, type, classification code, total rooms), status (`draft` / `submitted`), saved totals (check-ins, guest-nights, rooms occupied, residence split, sex, sales, by country / by region, filled days), `zeroDays`, `prevMonthLastDayGuests`, optional `seed: demo`.
- Subcollection `rows`: one doc per room-night.
- Rules: hotel (aeId == auth uid) reads/writes its months; LGU reads its municipality; OPTACA / Governor read all; staff may write **demo-seeded** data only and may delete. Demo seeding / purge writes are not signed.

### Insights

Establishment Insights, Governor entity analytics and the read-only viewer share one board: occupancy (month-to-date for the current month), ALOS, persons per room, residence / sex mix, top origins, room ranking, ADR / RevPAR, completeness, MoM / YoY, recommendations. DSS hints unlock gradually (locked < 7 filled days, soft from 7, full from 30).

### Do not

- Re-introduce tourist-side hotel stays or establishment reviews without a new product decision.
- Type totals that the calculator derives.
- Rebuild DOT exporters when register fields are added — only extend fillers.

### Hotel Reports tab

Lodging establishments get a **Reports** tab: the shared `DotReportExportPanel` locked to their own register (`lockedEstablishment`) with only their forms (DAE-1B, DAE-1A, DAE 1B.2, DAE 1B.2 Dom, plus CUS MICE when they host events). Same preview → Excel → PDF as LGU Analytics.

---

## 2b. Venue MICE log (CUS MICE)

Source workbook: `forms_format/CUS-FORM-MICE-UTILIZATION-SURVEY-FORM.xlsx` (sheets **CUS SUMMARY** and **CUS BY EST**; also bundled as an app asset as the template fallback).

### Locked decisions

1. **Opt-in per venue:** Profile → DOT reporting profile → “We host events (MICE)” (`hostsMice` on `accommodation_establishments`). Default on only for category “events place”. On = **Events** tab + CUS form in Reports.
2. **One row = one event** (multi-day events are one row with a date range; hours = total for the whole event). Month = month of the start date.
3. **Typed:** date(s), event name, hours, type, foreign, local, male / female, optional exhibit (exhibitors, visitors), organizer (name, address, contact person, tel.), remarks, optional foreign-country breakdown (analytics only — not on the official sheet).
4. **Computed, never typed:** CN (control number per venue-month in date order), total attendees (= foreign + local; male + female must match), month totals, category / country breakdowns.
5. **Event type:** autocomplete over 33 suggestions (`MiceEventTypes.base`, each mapped to a `MiceCategory`) plus the venue’s custom types (`mice_venue_settings/{aeId}.customTypes`). A new label is added inline (“Add “X” as a new type”) with a category picked once; it is saved only after the event saves.
6. **Submit month:** a month with zero events can be submitted as a **nil report** (“no events”). Back to draft needs a reason. Every add / edit / duplicate / delete / submit / reopen is a sign-off (`subjectType: mice_register`).
7. **Views:** month (editable), quarter, year (read-only rollups; a row opens its month). Filters: category chips, exhibits only, with foreign guests, search, sort; the TOTAL footer reflects the filtered rows. Sheets: Events · Summary · Sign-offs.

### Data shape

- Header `mice_monthly_reports/{aeId}_{yyyy}_{mm}`: venue identity, `periodKey`, status (`draft` / `submitted`), saved totals (events, hours, foreign, local, male, female, exhibitions, exhibitors, visitors, multi-day, by category, by country), `lastSignOff`, optional `seed: demo`.
- Subcollection `events`: one doc per event (`seed: demo` for demo data).
- Rules: same model as `ae_monthly_reports` (path-based get for the owner, list must filter by `aeId` / `municipalityId`); `mice_venue_settings/{aeId}` owner write, staff read.

### CUS export (Analytics, Reports tab)

- Query: `fetchMiceReportData` (`lib/utils/mice_report_query.dart`) — venue › LGU › province scope; events counted by start date within the range; filters: categories, include drafts.
- Preview = CUS SUMMARY rows (venue column only when several venues) + TOTAL footer; same rows in the PDF.
- Excel (`buildCusWorkbook`): official template from Supabase → bundled asset → equivalent built workbook. Layout option: **Summary + one CUS BY EST sheet per venue** (default) · summary only · per venue only; one venue in scope always gets its BY EST sheet. Rows beyond the template’s 20 are inserted (footer shifts). Hidden helper sheets removed. `ATMOS_DATA` (rows, by category, by country) + `ATMOS_GAPS`.
- Footer names (“Name of Tourism Officer”, “Mayor”) are typed in the panel, remembered per LGU on the device, printed on BY EST and as PDF signatory lines. PDF also prints the latest venue sign-off per venue-month.
- Compliance: the register compliance table shows a **MICE (CUS)** column (events / no events / draft / not logged), MICE KPIs and a “MICE not submitted” filter; event-only venues appear with “No rooms”.

---

## 3. OPTACA (related)

LGU submit packages should eventually attach the same generated Excel/PDF. Until that slice lands, packages may remain metrics/notes only — extend `lgu_report_submission_service`, do not invent a second inbox.

---

## 4. One-line policy

> Attraction QR feeds VAR; hotel DOT registers feed DAE; venue MICE logs feed CUS; Analytics always shows best-fill preview with gaps; primary downloads are Excel + PDF — never blank official as the happy path.
