# Build Flutter web and deploy to Firebase Hosting (atmos-trs-system).
# Run from repo:  .\scripts\deploy_firebase_hosting.ps1
# Requires: flutter, firebase CLI, logged in (firebase login)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host "Preparing optional web assets..."
if (-not (Test-Path "web\tripplan.png")) {
  if (Test-Path "assets\images\tripplan.png") {
    Copy-Item "assets\images\tripplan.png" "web\tripplan.png" -Force
  }
}
if (-not (Test-Path "web\fonts")) {
  New-Item -ItemType Directory -Path "web\fonts" -Force | Out-Null
}
$fontSrc = "assets\fonts\holiday-calling-non-commercial-use.noncommercialuse.ttf"
if ((Test-Path $fontSrc) -and -not (Test-Path "web\fonts\holiday-calling-non-commercial-use.noncommercialuse.ttf")) {
  Copy-Item $fontSrc "web\fonts\" -Force
}

Write-Host "Building Flutter web (release)..."
flutter build web --release --no-tree-shake-icons
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Deploying to Firebase Hosting..."
firebase deploy --only hosting --project atmos-trs-system
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Done. Open your Hosting URL from the deploy output above"
Write-Host "(typically https://atmos-trs-system.web.app or https://atmos-trs-system.firebaseapp.com)."
