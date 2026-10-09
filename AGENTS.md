# Atmos TRS — Agent briefing (always read)

This is **not a greenfield project**. Existing Flutter + Firebase code is the starting point.

**Full handoff:** `docs/PROJECT_CONTEXT.md`  
**Locked product decisions:** `docs/atmos-forms-and-establishment-qr.md`  
**Team rules:** `.cursor/rules/atmos-trs-scope.mdc` (always), `.cursor/rules/atmos-product-workflow.mdc` (LGU/reports), `.cursor/rules/auto-run-commands.mdc`

## What this product is

**Atmos TRS** (Misamis Occidental) — tourist registration, QR check-in, LGU municipal tourism, OPTACA / Provincial Tourism, Governor analytics, accommodation establishments, DOT report Excel/PDF export.

**Data flow:** Tourist registered → QR (attraction / LGU) → LGU analytics → DOT preview + Excel/PDF → optional OPTACA package → Governor aggregates. Hotels enter a monthly **DOT register (DAE-1B)** on the establishment dashboard → DAE forms + LGU/OPTACA/Governor insights.

## Roles (do not invent new ones)

`tourist` · `tourism` / `tourism_office` (LGU) · `provincial_tourism` / `tourism_province` (OPTACA) · `governor` · `tourism_establishment`

## Default ownership

Primary work area: **LGU municipal tourism + DOT/OPTACA reports** (+ seeding). Other roles are fair game when the user asks — do not drive-by edit them.

## Locked policies (never violate)

1. **DOT:** Every Analytics form gets a filled preview; gaps via `ATMOS_GAPS`; primary downloads Excel + PDF of that fill; one pipeline only (aggregate → preview → Excel → PDF). No second exporter stack.
2. **Data routing:** Attraction / LGU QR → **VAR** family. Hotel DOT registers (`ae_monthly_reports`) → **DAE** family. Do not mix without labeling proxies.
3. **Establishment register:** Hotels type guests per occupied room-night into the DAE-1B Daily Register (one row = one room-night); totals (occupancy = rooms occupied ÷ rooms available, ALOS = guest-nights ÷ check-ins) are computed, never typed. No establishment QR stays, no establishment reviews (both retired). Drafts count in DOT figures with a gap note.
4. Prefer **seeding** (`tools/seed_*.js`, LGU Debug data) over editing other-role modules for demos.
5. Ask before: shared auth / role→route, global Firestore rules, other-role dashboard one-offs.
6. Never commit/push unless asked. Never commit secrets (`.env`, keys).

## How to work

Inspect → Understand → Plan → **Extend** existing code → Verify. Full slices (no stub-only). Minimal diffs. Flutter SDK: `C:\flutter\bin`.
