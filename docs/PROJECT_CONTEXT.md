# Atmos TRS — Project Context (account / chat handoff)

Use this when starting on a **new Cursor account** or a cold chat. Prefer this + `.cursor/rules/` over any assumed chat memory.

---

## Project

**Atmos TRS** — Tourism Registration System for Misamis Occidental.

## Purpose

Register tourists, capture visits via QR, let LGU tourism offices analyze and export DOT forms, submit packages to OPTACA (provincial), and surface aggregates for the Governor. Accommodation establishments fill a monthly DOT register (DAE-1B) that feeds DAE-family reports and LGU / OPTACA / Governor insights.

## Tech stack

- **App:** Flutter / Dart (Windows primary local; also Android / web)
- **SDK path:** `C:\flutter\bin`
- **Backend:** Firebase Auth, Cloud Firestore, Cloud Functions, FCM
- **Reports storage/templates:** Supabase (templates + storage only — not primary app DB)
- **Email:** EmailJS
- **Rules / seeds:** `firestore.rules`, `functions/index.js`, `tools/seed_*.js`, `tools/cleanup_*.js`

## Roles → surfaces

| Role | Keys | Primary UI |
|------|------|------------|
| Tourist | `tourist` | Home / QR / visit history |
| LGU municipal tourism | `tourism` / `tourism_office` | `lib/screens/tourism_dashboard.dart` |
| OPTACA / Provincial | `provincial_tourism` / `tourism_province` | Provincial dashboard + `optaca_report_review_panel` |
| Governor | `governor` | Governor dashboard |
| Establishment (hotel / AE) | `tourism_establishment` | `establishment_dashboard_screen.dart` |

Canonical profile shape: `lib/services/user_directory_service.dart`, `lib/config/session_storage.dart`.

## Important architecture

### Default AI ownership

**LGU + DOT/OPTACA reports + seeds.** Upstream (tourist/QR) and downstream (Governor) are integration context unless the user expands scope.

| Area | Paths |
|------|--------|
| LGU | `tourism_dashboard.dart`, `lib/widgets/lgu_*`, LGU services |
| DOT | `lib/utils/dot_*`, `dae3_*`, `provincial_report_*`, `checkin_report_*`, `lib/widgets/dot_*`, `supabase_report_*` |
| LGU → OPTACA | `lgu_report_submission_service`, `lgu_submit_report_to_optaca_panel`, `optaca_report_review_panel` |
| AE register | `ae_register_service.dart`, `ae_register_calculator.dart`, `lib/widgets/ae_register/`, establishment dashboard, `ae_register_report_query.dart` (DAE) |
| Seeds | `tools/seed_*.js`, `lgu_debug_data_*`, cleanup tools |

### Data flow

```
Tourist signup
  → Attraction / LGU QR check-in          → VAR-family DOT forms
Hotel DOT register (DAE-1B, monthly)     → DAE-family DOT forms + AE insights
  → LGU Analytics (preview + Excel/PDF)
  → optional OPTACA submission package
  → Governor aggregates
```

### DOT pipeline (one only)

`aggregate → preview → Excel writer → PDF writer`

- Extend: `dot_report_preview`, `dot_report_export_service`, `dot_report_pdf_export`, `DotReportExportPanel`
- **Do not** invent a second XLSX/PDF/email stack
- Blank official template = advanced/secondary only

### Establishment register model (locked)

1. Hotel logs in → Register tab = DAE-1B Daily Register (one row = one occupied room-night)  
2. Monthly Record / DAE-2 / By Country are computed (occupancy = rooms occupied ÷ rooms available; ALOS = guest-nights ÷ check-ins)  
3. Data: `ae_monthly_reports/{aeId}_{yyyy}_{mm}` header (saved totals) + `rows` subcollection; hotel submits the month  
4. LGU / OPTACA see submitted / draft / missing per AE; Governor drills into Insights; DAE forms read registers (drafts flagged)  
5. Retired: establishment QR stay requests, staff guest confirm, rooms tab, establishment reviews  
6. Venues with “We host events (MICE)” on log events (Events tab) → `mice_monthly_reports` + `events` → CUS MICE form (CUS SUMMARY + one CUS BY EST per venue)  

Deploy `firestore.rules` for client writes. Spec: `docs/atmos-forms-and-establishment-qr.md`.

## Current progress (snapshot — update when big slices land)

### In place / implemented in code

- Multi-role Flutter app (tourist, LGU, OPTACA, Governor, establishment)
- QR check-in (attraction / LGU) and related welcome / pending-completion flows
- LGU dashboard: tourists, analytics, DOT export panels, debug seed UI
- DOT filled preview + Excel + PDF pipeline (`dot_report_*`)
- LGU → OPTACA submit panel + OPTACA review panel (extend; file attachments may still be incomplete)
- Establishment DOT register (DAE-1B) + Insights; LGU/OPTACA compliance table; DAE forms filled from registers
- Hotel Reports tab (own DAE forms) + venue MICE log (Events tab) → CUS MICE preview / Excel / PDF; MICE status in the compliance table
- Seed / cleanup tooling for demos (`seed_dashboard_analytics.js`, `seed_dummy_data.js`, etc.)

### Still evolving / typical next work

- Register columns for non-lodging establishment types (schema is extensible; lodging done first)
- PSA / DOT country–region mapping tables for cleaner VAR/DAE cells
- OPTACA packages attaching the same generated Excel/PDF
- Upload the CUS template to the Supabase “Report template” bucket (the app falls back to the bundled copy)
- Deploy/verify Firestore rules + Functions wherever environments lag local code

### Demo / seed

See `docs/TEST_ACCOUNTS_REPORTS.md`. Prefer **Settings → Debug data → Seed tourist data** or `node tools/seed_dashboard_analytics.js` for charts. Seed emails use `@misocc-seed.ph` / demo `@misocc-demo.ph`.

## Coding style (AI)

- Keep existing architecture; extend, don’t rewrite working systems
- Prefer reusable widgets/services already in tree
- Follow existing naming; don’t change navigation / role routing unless requested
- Minimal diffs; no drive-by refactors
- Full requested slice — no TODO-only stubs unless asked
- Run `flutter analyze` / `dart analyze` when useful; hot restart if `flutter run` is active
- Temporary cross-scope edits only to test: small, reversible, explained

## How AI should work with this user

- Explain before major architectural changes
- Don’t modify unrelated files
- Preserve existing functionality
- Ask before large architectural changes, shared auth/routing, or global Firestore rules
- Follow project rules over chat history from other accounts
- Never commit or push unless explicitly asked
- Never commit `.env` or secrets
- Do not claim a feature works until the role workflow was verified (or say what was not run)
- Communication: concise; answer first; flag speculation

## Sources of truth (read order)

1. `AGENTS.md` (this briefing at repo root)
2. `.cursor/rules/atmos-trs-scope.mdc`
3. `.cursor/rules/atmos-product-workflow.mdc` (when touching LGU/DOT/AE/OPTACA)
4. `docs/atmos-forms-and-establishment-qr.md`
5. `docs/TEST_ACCOUNTS_REPORTS.md` / `docs/DOT_REPORT_ATMOS_FIELD_AUDIT.md` as needed
6. This file’s **Current progress** section for “where we left off”
