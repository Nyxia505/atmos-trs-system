# ATMOS ORS Directions Worker

Proxies **OpenRouteService** so the Flutter web app never embeds the API key.

## One-time setup

1. Create a free [OpenRouteService](https://openrouteservice.org/dev/#/signup) key (or HeiGIT key).
2. From this folder:

```powershell
cd cloudflare-workers\ors-directions
npm install
npx wrangler login
npx wrangler secret put ORS_API_KEY
npx wrangler deploy
```

3. Copy the Worker URL (e.g. `https://atmos-ors-directions.<subdomain>.workers.dev`).
4. Set Flutter config in `linontripplanner-main/lib/config.dart`:

```dart
const String kOrsDirectionsProxyUrl =
    'https://atmos-ors-directions.<subdomain>.workers.dev/directions';
```

Or build with:

```powershell
flutter build web --release --dart-define=ORS_DIRECTIONS_PROXY_URL=https://….workers.dev/directions
```

5. Redeploy hosting: `powershell -File tools\deploy_web.ps1`

## API

`POST /directions`

```json
{ "coordinates": [[123.7981, 8.4930], [123.6501, 8.5486]] }
```

Success:

```json
{
  "provider": "openrouteservice",
  "points": [{ "lat": 8.49, "lng": 123.79 }, ...],
  "distanceMeters": 31300,
  "durationSeconds": 2480,
  "pointCount": 120
}
```

## Notes

- CORS allows `atmos-trs-system.web.app` and localhost.
- Upstream default: HeiGIT `…/driving-car/geojson` (override with `ORS_UPSTREAM` var).
- Does **not** require Firebase Blaze or Google Maps billing.
