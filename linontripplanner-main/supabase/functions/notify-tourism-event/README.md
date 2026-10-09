# notify-tourism-event (FCM push without Firebase Blaze)

Sends an FCM notification to topic `tourism_events` when an admin creates an event.

## 1. Firebase service account

1. Open [Firebase Console](https://console.firebase.google.com/project/atmos-trs-system/settings/serviceaccounts/adminsdk)
2. **Generate new private key** → save the JSON file (do not commit it)

## 2. Set the secret in Supabase

```powershell
cd main
npx supabase login
npx supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(Get-Content -Raw 'C:\path\to\your-service-account.json')" --project-ref cgpjqkbbmyxvitwpkikn
```

Or: Supabase Dashboard → **Edge Functions** → **Secrets** → add `FIREBASE_SERVICE_ACCOUNT_JSON` (paste the full JSON).

## 3. Deploy

```powershell
cd main
npx supabase functions deploy notify-tourism-event --project-ref cgpjqkbbmyxvitwpkikn
```

## 4. Test

1. Hot-restart the Flutter app on a **phone** (Allow notifications)
2. As admin, **Add event** → Save
3. Phone(s) subscribed to `tourism_events` should get: `New event: …`
