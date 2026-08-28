# SMS & email OTP setup (Semaphore + Firebase)

Tourist signup sends the 6-digit verification code to:

1. **Email inbox** — Gmail SMTP (recommended) or EmailJS fallback via `sendOtpEmail`
2. **Phone notification** — FCM push + on-device notification on mobile (verify screen)
3. **SMS** (optional) on the **mobile number** entered in the signup form (`sendOtpSms` → Semaphore)

On **mobile**, the code also appears in the notification shade so users do not need to dig through Spam.

---

## Email inbox (avoid Spam folder)

**Recommended:** send from an official Gmail / Google Workspace account using SMTP in Cloud Functions.

1. In Google Account → Security, enable **2-Step Verification**.
2. Create an **App Password** for “Mail”.
3. Add to `functions/.env` (do not commit):

```env
GMAIL_SMTP_USER=tourismoffice.atmos@misocc-demo.ph
GMAIL_SMTP_APP_PASSWORD=your-16-char-app-password
OTP_INBOX_REPLY_TO=tourismoffice.atmos@misocc-demo.ph
OTP_INBOX_FROM_NAME=ATMOS-TRS Tourism
```

4. Deploy:

```powershell
firebase deploy --only functions:sendOtpEmail
```

If SMTP is not configured, the function falls back to **EmailJS**. In the EmailJS dashboard, set your OTP template **Subject** to `Complete your ATMOS-TRS registration` and use `{{message}}` or `{{otp}}` in the body (avoid “OTP” in the subject — spam filters flag it).

---

## Step 1 — Semaphore account

1. Go to [https://semaphore.co](https://semaphore.co) and create an account.
2. **Load credits** (each SMS uses credits; OTP route uses **2 credits** per message).
3. Open **API** in the dashboard and copy your **API key**.
4. Register a **Sender Name** (e.g. `ATMOS`):
   - Dashboard → Sender Names → request/add name
   - Wait for approval (required before SMS works)
   - Use the **exact** approved name in config below

---

## Step 2 — Store secrets in Firebase

From the project root (`atmos_trs_system`), in PowerShell:

```powershell
# Log in and select project
firebase login
firebase use atmos-trs-system

# API key (paste when prompted — input is hidden)
firebase functions:secrets:set SEMAPHORE_API_KEY
```

Optional sender name (must match Semaphore dashboard):

```powershell
# Option A: secret/env via functions .env (see Step 3)
# Option B: set at deploy time in functions/.env
```

---

## Step 3 — Sender name (optional)

Create `functions/.env` (do **not** commit real keys to git):

```env
SEMAPHORE_SENDER_NAME=ATMOS
```

Use the sender name Semaphore approved for your account. If omitted, the code defaults to `ATMOS`.

---

## Step 4 — Deploy Cloud Functions

```powershell
cd c:\atmos_trs_system
firebase deploy --only functions:sendOtpSms
```

For first-time secret binding, deploy **all** functions once:

```powershell
firebase deploy --only functions
```

Or run the helper script:

```powershell
.\scripts\deploy_sms_otp.ps1
```

---

## Step 5 — Test

1. Run the app on a **real Android phone** (SMS does not apply on Chrome/web the same way).
2. Sign up with a valid PH mobile: `09XXXXXXXXX`.
3. After submit, check **SMS on that number** (not the signup device notification).
4. Enter the code on **Verify OTP** screen.

**Resend:** On verify screen, tap **Resend code** — SMS is sent again to the mobile saved in `tourists/{uid}.mobile`.

---

## Troubleshooting

| Symptom | Fix |
|--------|-----|
| “SMS skipped” / email only | `SEMAPHORE_API_KEY` not set or function not redeployed after setting secret |
| Semaphore sender error | Register and approve sender name; match `SEMAPHORE_SENDER_NAME` |
| No SMS, email works | Low credits, wrong number format, or telco delay — check Semaphore dashboard message log |
| `permission-denied` mobile | Resend must use same number as signup profile |
| Function `not-found` | Run `firebase deploy --only functions:sendOtpSms` |

View function logs:

```powershell
firebase functions:log --only sendOtpSms
```

---

## Code references

- Cloud Function: `functions/index.js` → `sendOtpSms`
- Flutter client: `lib/services/otp_delivery_service.dart` → `sendOtpSms` / `deliverVerificationCode`
- Signup calls SMS: `lib/screens/signup_screen.dart` (Step 5)
- Resend calls SMS: `lib/screens/verify_otp_screen.dart`
