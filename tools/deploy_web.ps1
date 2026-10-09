# Builds Flutter web, cache-busts the entry scripts, and deploys Firebase Hosting.
#
# Flutter output names (main.dart.js, flutter_bootstrap.js, ...) never change
# between builds, so browsers that cached them keep running the old app.
# A per-deploy ?v= stamp on those URLs forces a fresh download.
#
# Usage:  powershell -ExecutionPolicy Bypass -File tools\deploy_web.ps1 [-SkipBuild] [-SkipDeploy]

param(
  [switch]$SkipBuild,
  [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$WebDir = Join-Path $Root 'build\web'
$Flutter = 'C:\flutter\bin\flutter.bat'

Push-Location $Root
try {
  if (-not $SkipBuild) {
    & $Flutter build web --release --no-wasm-dry-run
    if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }
  }

  $stamp = Get-Date -Format 'yyyyMMddHHmmss'

  $indexPath = Join-Path $WebDir 'index.html'
  $index = [IO.File]::ReadAllText($indexPath)
  $index = [regex]::Replace(
    $index,
    'src="(flutter_bootstrap\.js|directions_bridge\.js)(\?v=[^"]*)?"',
    { param($m) 'src="' + $m.Groups[1].Value + '?v=' + $stamp + '"' }
  )
  [IO.File]::WriteAllText($indexPath, $index)

  $bootstrapPath = Join-Path $WebDir 'flutter_bootstrap.js'
  $bootstrap = [IO.File]::ReadAllText($bootstrapPath)
  $bootstrap = [regex]::Replace(
    $bootstrap,
    '"mainJsPath":"main\.dart\.js(\?v=[^"]*)?"',
    ('"mainJsPath":"main.dart.js?v=' + $stamp + '"')
  )
  [IO.File]::WriteAllText($bootstrapPath, $bootstrap)

  if (-not $index.Contains("flutter_bootstrap.js?v=$stamp") -or
      -not $bootstrap.Contains("main.dart.js?v=$stamp")) {
    throw 'Cache-bust stamp not applied (index.html / flutter_bootstrap.js format changed?)'
  }
  Write-Host "Cache-bust stamp: $stamp"

  if (-not $SkipDeploy) {
    firebase deploy --only hosting
    if ($LASTEXITCODE -ne 0) { throw 'firebase deploy failed' }
  }
}
finally {
  Pop-Location
}
