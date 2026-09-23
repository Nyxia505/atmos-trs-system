# Camera QR → App Links (ops checklist)

Phone-camera QR codes now encode:

`https://atmos-trs-system.web.app/checkin?type=…&…`

(not a hash URL), so Android can hand them to the installed ATMOS app.

## Enable verified App Links

1. Get **SHA-256** of the signing cert (debug + Play App Signing).
2. Put fingerprints in `web/.well-known/assetlinks.json` (replace `REPLACE_WITH_DEBUG_OR_PLAY_SHA256`).
3. Deploy Hosting so  
   `https://atmos-trs-system.web.app/.well-known/assetlinks.json` is public.
4. Rebuild/reinstall the Android app.
5. Verify:  
   `adb shell pm get-app-links com.atmos.trs`

Until verified, Android may still offer “Open with ATMOS” / browser chooser.

## Flows

| Case | Behavior |
|------|----------|
| App installed | App Link → pending QR saved → `/qr-welcome` or `/qr-resume` |
| No app | Browser landing → Get app (Play referrer carries `atmos_q`) → signup → resume or rescan |
| In-app Scan tab | Unchanged natural flow |

Legacy `#/landing?…` QRs still parse on web.
