# Generate dart_defines.json from .env, then flutter run with Supabase upload keys.
param(
  [string]$Device = 'chrome',
  [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

& "$PSScriptRoot\gen_dart_defines.ps1"
$flutter = if (Test-Path 'C:\flutter\bin\flutter.bat') {
  'C:\flutter\bin\flutter.bat'
} else {
  'flutter'
}

& $flutter run -d $Device --dart-define-from-file=dart_defines.json @ExtraArgs
