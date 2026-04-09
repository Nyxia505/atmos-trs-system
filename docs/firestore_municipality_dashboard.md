# Firestore setup for municipality-based dashboard

## 1. `users` collection (dashboard accounts)

Create one document per municipal tourism office account. **Do not store passwords**; use Firebase Auth for login.

- **Collection:** `users`
- **Query:** App looks up by `email` (use lowercase for consistency).

### Document fields

| Field         | Type   | Required | Description |
|---------------|--------|----------|-------------|
| `email`       | string | Yes      | Same as Firebase Auth email (e.g. lowercase). |
| `role`       | string | Yes      | Use `tourism` for municipal dashboard. |
| `municipality`| string | Yes      | Display name for the LGU (e.g. "Tangub City", "Oroquieta City"). |

### Example documents

- Tangub City: `email: "tourism.tangub@misocc.gov.ph"`, `role: "tourism"`, `municipality: "Tangub City"`
- Oroquieta City: `email: "tourism.oroquieta@misocc.gov.ph"`, `role: "tourism"`, `municipality: "Oroquieta City"`
- Ozamiz City: `email: "tourism.ozamiz@misocc.gov.ph"`, `role: "tourism"`, `municipality: "Ozamis City"`
- Sinacaban, Tudela, Jimenez: same pattern with their municipality name.

After login, the app fetches the profile by email and restricts the dashboard to check-ins where `municipalityId` matches the assigned municipality.

**One LGU, one dashboard account:** A single `users` row + Firebase Auth user (e.g. `tourism.ozamiz@misocc.gov.ph`) is enough for **all** tourist spots in that municipality (e.g. Asenso Ozamiz Wellness Park and Cotta Fort & Shrine both fall under Ozamiz—no separate tourism login per spot).

---

## 2. `tourist_spots` collection

Each spot must have at least:

| Field          | Type   | Required | Description |
|----------------|--------|----------|-------------|
| `name`         | string | Yes      | Spot name. |
| `municipality` | string | Yes      | Display name (e.g. "Tangub City"). |
| `category`     | string | Yes      | e.g. "Park", "Heritage". |
| `municipalityId` | string | Optional | Canonical id (e.g. tangub, oroquieta). If missing, derived from `municipality`. |

Document ID = `spot_id` (encoded in the spot’s QR code).

### LGU (municipality) QR — separate from spot QR

Each LGU has a **unique municipality QR** (not tied to a single spot), format:

`ATMOS-TRS-LGU:<municipalityId>` (e.g. `ATMOS-TRS-LGU:ozamiz`)

The tourism dashboard and governor dashboard can **download** this as PNG/PDF for posters. Scanning it in the app opens municipality info / map (spot-level check-in still uses **spot** QR codes).

### 6 tourist areas (reference)

| Spot name | Municipality |
|-----------|---------------|
| Asenso Global Gardens | Tangub City |
| Asenso Misamis Occidental Aquamarine Park | Sinacaban |
| Asenso Ozamiz Wellness Park & Cotta Fort & Shrine | Ozamis City |
| Tudela Highland Resort & Eco Park | Tudela |
| Oroquieta City Boulevard and People's Park | Oroquieta City |
| St. John the Baptist Church | Jimenez |

Use **separate Firestore documents** (and QR codes) for each physical spot if you want distinct check-ins—e.g. one doc for the wellness park and one for Cotta Fort—while still using the **same** `tourism.ozamiz@…` LGU login for the dashboard.

Add these (or your own) in Firestore with `name`, `municipality`, `category`, and optional `municipalityId`. Use the document ID as the `spot_id` in QR codes.

---

## 3. `qr_checkins` collection

Written by the app when a tourist scans a spot QR. Each document has:

- `tourist_id`, `spot_id`, `spot_name`, `municipality`, `municipalityId`, `timestamp`

Dashboard queries filter by `municipalityId` matching the logged-in admin’s municipality (from the `users` profile).
