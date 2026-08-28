# Deploy Semaphore SMS OTP Cloud Function for ATMOS TRS
# Prerequisites: firebase CLI, Blaze plan, SEMAPHORE_API_KEY secret set

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

Write-Host "ATMOS TRS — deploy sendOtpSms (Semaphore SMS OTP)" -ForegroundColor Cyan
Write-Host ""

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Write-Error "firebase CLI not found. Install: npm install -g firebase-tools"
}

Write-Host "Checking Firebase project..." -ForegroundColor Yellow
firebase use

Write-Host "Ensure secret is set: firebase functions:secrets:set SEMAPHORE_API_KEY" -ForegroundColor Gray
Write-Host "Semaphore dashboard: https://semaphore.co" -ForegroundColor Gray

Write-Host ""
Write-Host "Deploying functions (sendOtpSms requires secrets binding on full deploy)..." -ForegroundColor Yellow
firebase deploy --only functions:sendOtpSms,functions:sendOtpEmail

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Done. Test signup on a real phone with 09XXXXXXXXX." -ForegroundColor Green
    Write-Host "Docs: docs/SMS_OTP_SETUP.md" -ForegroundColor Gray
} else {
    Write-Error "Deploy failed. Try: firebase deploy --only functions"
}
