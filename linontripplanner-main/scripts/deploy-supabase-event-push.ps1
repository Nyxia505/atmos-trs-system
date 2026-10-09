# One-time setup: deploy Supabase FCM push (no Firebase Blaze)
# 1) Download Firebase service account JSON (Generate new private key)
# 2) Save it as: main\secrets\firebase-service-account.json
# 3) Run this script from main\:  .\scripts\deploy-supabase-event-push.ps1
#    Paste a Supabase access token when prompted (Account → Access Tokens)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$saPath = Join-Path $root "secrets\firebase-service-account.json"
$projectRef = "cgpjqkbbmyxvitwpkikn"

if (-not (Test-Path $saPath)) {
  Write-Host ""
  Write-Host "Missing: $saPath"
  Write-Host "1. Open Firebase → Project settings → Service accounts → Generate new private key"
  Write-Host "2. Save the file as: secrets\firebase-service-account.json"
  Write-Host "3. Re-run this script"
  Start-Process "https://console.firebase.google.com/project/atmos-trs-system/settings/serviceaccounts/adminsdk"
  New-Item -ItemType Directory -Force -Path (Join-Path $root "secrets") | Out-Null
  exit 1
}

if (-not $env:SUPABASE_ACCESS_TOKEN) {
  Write-Host ""
  Write-Host "Need a Supabase access token (browser login does not work from this script)." -ForegroundColor Yellow
  Write-Host "Opening https://supabase.com/dashboard/account/tokens"
  Start-Process "https://supabase.com/dashboard/account/tokens"
  Write-Host "Click Generate new token, copy it, then paste below."
  $token = Read-Host "Paste SUPABASE access token"
  if ([string]::IsNullOrWhiteSpace($token)) { throw "No token provided" }
  $env:SUPABASE_ACCESS_TOKEN = $token.Trim()
}

Write-Host "Logging into Supabase with token..."
npx --yes supabase login --token $env:SUPABASE_ACCESS_TOKEN --no-browser --agent no
if ($LASTEXITCODE -ne 0) { throw "supabase login failed" }

Write-Host "Setting FIREBASE_SERVICE_ACCOUNT_JSON secret..."
$json = Get-Content -Raw $saPath
npx --yes supabase secrets set "FIREBASE_SERVICE_ACCOUNT_JSON=$json" --project-ref $projectRef --agent no
if ($LASTEXITCODE -ne 0) { throw "secrets set failed" }

Write-Host "Deploying notify-tourism-event..."
npx --yes supabase functions deploy notify-tourism-event --project-ref $projectRef --no-verify-jwt --agent no
if ($LASTEXITCODE -ne 0) { throw "deploy failed" }

Write-Host ""
Write-Host "Done. Hot-restart the phone app, then Add event as admin to test push." -ForegroundColor Green
