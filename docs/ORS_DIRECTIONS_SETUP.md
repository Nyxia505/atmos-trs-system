# OpenRouteService blue-line setup (no Google Billing / no Firebase Blaze)

ATMOS draws the in-app blue road line from **OpenRouteService** through a **Cloudflare Worker**. The ORS API key never ships in Flutter web.

## Architecture

```
SpotDirectionsRoutePage
  → TripRouteMapView / PolylineLayer
  → getDirectionsRoute()
       1. Cloudflare Worker → HeiGIT OpenRouteService (primary)
       2. Public OSRM (fallback)
       3. Google (last resort; needs billing)
```

## Deploy the Worker

```powershell
cd cloudflare-workers\ors-directions
npm install
npx wrangler login
npx wrangler secret put ORS_API_KEY
# paste your key from https://openrouteservice.org/dev/#/signup
npx wrangler deploy
```

Copy the printed URL, e.g. `https://atmos-ors-directions.<account>.workers.dev`.

## Point Flutter at the Worker

Edit `linontripplanner-main/lib/config.dart` default, **or** build with:

```powershell
flutter build web --release --no-wasm-dry-run `
  --dart-define=ORS_DIRECTIONS_PROXY_URL=https://atmos-ors-directions.<account>.workers.dev/directions
```

Then:

```powershell
powershell -ExecutionPolicy Bypass -File tools\deploy_web.ps1 -SkipBuild
```

(or full `deploy_web.ps1` if you did not build yet)

## Verify

1. Desktop Chrome + Android Chrome → open a Misamis Occidental spot → Get Directions  
2. Expect a **blue road polyline** and real km / minutes (not a Haversine guess)  
3. DevTools console: `[directions] provider=openrouteservice httpStatus=200 … points=N`  
4. Kill the Worker / bad key → Retry banner above the sheet; pins remain; **Start** still opens Google Maps  

## Files

| Path | Role |
|------|------|
| `cloudflare-workers/ors-directions/` | Worker source + wrangler |
| `linontripplanner-main/lib/config.dart` | `kOrsDirectionsProxyUrl` |
| `linontripplanner-main/lib/directions_service.dart` | ORS primary fetch + retries |
| `lib/screens/spot_directions_route_page.dart` | Real road ETA only; retry UI |
