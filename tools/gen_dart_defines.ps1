# Generates dart_defines.json + lib/config/supabase_secrets.local.dart from .env.
# Local secrets file lets plain `flutter run` upload to Supabase (no dart-define needed).
# Never commit filled secrets — supabase_secrets.local.dart is gitignored.

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root '.env'
$OutFile = Join-Path $Root 'dart_defines.json'
$SecretsFile = Join-Path $Root 'lib\config\supabase_secrets.local.dart'

function Read-DotEnv([string]$Path) {
  $map = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $map }
  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { return }
    $i = $line.IndexOf('=')
    if ($i -lt 1) { return }
    $k = $line.Substring(0, $i).Trim()
    $v = $line.Substring($i + 1).Trim().Trim('"').Trim("'")
    $map[$k] = $v
  }
  return $map
}

function Escape-DartString([string]$Value) {
  return $Value.Replace('\', '\\').Replace("'", "\'")
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
  Write-Error 'Missing .env - copy from .env.example and fill Supabase keys.'
}

$envMap = Read-DotEnv $EnvFile
$defines = [ordered]@{}

foreach ($k in @(
  'SUPABASE_URL',
  'SUPABASE_BUCKET',
  'SUPABASE_ANON_KEY',
  'SUPABASE_SERVICE_ROLE_KEY'
)) {
  if ($envMap.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace($envMap[$k])) {
    $defines[$k] = $envMap[$k]
  }
}

if (-not $defines.Contains('SUPABASE_SERVICE_ROLE_KEY') -and -not $defines.Contains('SUPABASE_ANON_KEY')) {
  Write-Error 'Add SUPABASE_ANON_KEY (preferred) or SUPABASE_SERVICE_ROLE_KEY to .env'
}

$json = $defines | ConvertTo-Json -Compress
[System.IO.File]::WriteAllText($OutFile, $json)

$anon = if ($defines.Contains('SUPABASE_ANON_KEY')) { $defines['SUPABASE_ANON_KEY'] } else { '' }
$service = if ($defines.Contains('SUPABASE_SERVICE_ROLE_KEY')) { $defines['SUPABASE_SERVICE_ROLE_KEY'] } else { '' }
$anonEsc = Escape-DartString $anon
$serviceEsc = Escape-DartString $service

$dart = @"
# GENERATED from .env by tools/gen_dart_defines.ps1 — do not edit by hand.
# Gitignored — never commit real keys.

/// Local Supabase upload secrets (dev). Prefer anon key for production builds.
abstract final class SupabaseSecretsLocal {
  static const String anonKey = '$anonEsc';
  static const String serviceRoleKey = '$serviceEsc';
}
"@
# Fix: Dart uses // comments not #
$dart = @"
// GENERATED from .env by tools/gen_dart_defines.ps1 — do not edit by hand.
// Gitignored — never commit real keys.

/// Local Supabase upload secrets (dev). Prefer anon key for production builds.
abstract final class SupabaseSecretsLocal {
  static const String anonKey = '$anonEsc';
  static const String serviceRoleKey = '$serviceEsc';
}
"@

[System.IO.File]::WriteAllText($SecretsFile, $dart)

$keys = ($defines.Keys -join ', ')
Write-Host "Wrote dart_defines.json (keys: $keys)"
Write-Host "Wrote lib/config/supabase_secrets.local.dart"
Write-Host 'Hot restart Flutter (or re-run). Plain flutter run now has upload credentials.'
