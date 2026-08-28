# Run once per terminal session (or after opening Cursor):  . .\setup.ps1
$flutterBin = 'C:\flutter\bin'
if (-not (Test-Path "$flutterBin\flutter.bat")) {
    Write-Error "Flutter not found at $flutterBin. Install from https://docs.flutter.dev/get-started/install/windows"
    exit 1
}
if ($env:Path -notlike "*$flutterBin*") {
    $env:Path = "$flutterBin;$env:Path"
}
Set-Location $PSScriptRoot
Write-Host "Flutter: $(flutter --version 2>&1 | Select-Object -First 1)" -ForegroundColor Green
Write-Host "Project: $PSScriptRoot" -ForegroundColor Green
Write-Host "Run: flutter pub get" -ForegroundColor Cyan
Write-Host "     flutter run -d chrome" -ForegroundColor Cyan
