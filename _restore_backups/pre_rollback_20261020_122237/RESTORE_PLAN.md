# ATMOS TRS — restore plan (awaiting approval)

**Created:** 2026-10-20 12:22 (local)  
**Goal:** Undo Flutter code from prompt “FIX ATMOS TRS TOURIST SPOTS — SUPABASE STORAGE, MUNICIPALITY MAPS, AND DISCOVER”  
**Databases:** untouched (Firestore / Supabase Storage / Auth stay as-is)

## Backup of current working copies

This folder contains copies of 12 tourist-related Dart files as they existed **before** any rollback.

## Reliable restore point

| Source | ID | Notes |
|--------|-----|--------|
| Git commit (last on `main`) | `e4c2de7` (2026-10-19 01:16 +0800) — *Merge remote main into the OPTACA Trip Planner dashboard update.* | Only committed snapshot before today’s FIX work |
| Cursor checkpoints | none found | No project checkpoints dir |
| Cursor Local History | repo / display / model snapshots @ 2026-10-20 11:57 | **Identical to HEAD** for those 3 files |
| Cursor Local History | `home_screen` | Last snapshot **2026-08-22** — older than HEAD; **not** a safe “just before FIX” point |

There is **no** separate Git commit created by the FIX prompt (all of that work is uncommitted).

## Files that still differ from HEAD (FIX-related)

These are the only tourist files with a content diff vs `e4c2de7` right now:

1. `lib/services/tourist_spots_repository.dart` — expanded eligibility / municipality helpers  
2. `lib/models/tourist_spot_firestore.dart` — `status`, location→municipality parsing  
3. `lib/data/misamis_occidental_display_spots.dart` — `allEligibleFromFirestore`  
4. `lib/data/tourist_spot_image_catalog.dart` — prefer Supabase `image_url`; Kenjelo asset const  
5. `lib/features/home/home_screen.dart` — `allEligibleFromFirestore` + **Discover by Municipality** (+ some non-FIX uncommitted edits)

## Files already matching HEAD (no rollback needed)

- `lib/screens/municipality_map_and_spots_screen.dart`  
- `lib/screens/tourist_destination_detail_screen.dart`  
- `lib/features/explore/explore_mis_occ_screen.dart`  
- `lib/features/misamis_occidental/misamis_occidental_screen.dart`  
- `lib/config/supabase_storage_config.dart`  
- `lib/data/tourist_spots_by_municipality.dart`  
- `lib/models/tourist_destination_detail.dart`  

(Map / Nearby Tourist Spots / Explore sheet rewrites from the FIX prompt are **not** present in the working tree vs HEAD.)

## Proposed restoration options (choose one)

### Option A — Restore the 5 files from Git HEAD (`e4c2de7`)

Safe Git command (non-destructive):  
`git checkout HEAD -- <those 5 paths>`  
(or `git restore --source=HEAD -- <paths>`)

**Effect:** Removes FIX prompt changes.  
**Caveat:** `home_screen.dart` also loses other uncommitted edits mixed into the same file (profile email guard, VR-first featured sort, subtitle wording).

### Option B — Surgical (recommended if you want to keep other home tweaks)

1. Restore from HEAD: repository, firestore model, display_spots, image_catalog  
2. On `home_screen.dart` only: remove Discover-by-Municipality + switch `_allDestinationSpots` back to `mergeWithFirestore` — keep other home diffs

### Not proposed

- `git reset --hard` / `git clean -fd`  
- Touching Firestore, Supabase Storage, Auth, or credentials  
- Restoring Aug 2026 local-history `home_screen` (too old)

## Status

**Waiting for your approval** before applying Option A or B.
