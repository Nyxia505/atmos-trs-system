# Upload image assets to Supabase Storage bucket tourist-images.
# Requires project-root .env with SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_BUCKET.

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root '.env'

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

$envMap = Read-DotEnv $EnvFile
$SupabaseUrl = if ($envMap['SUPABASE_URL']) { $envMap['SUPABASE_URL'] } else { $env:SUPABASE_URL }
$ServiceKey = if ($envMap['SUPABASE_SERVICE_ROLE_KEY']) { $envMap['SUPABASE_SERVICE_ROLE_KEY'] } else { $env:SUPABASE_SERVICE_ROLE_KEY }
$Bucket = if ($envMap['SUPABASE_BUCKET']) { $envMap['SUPABASE_BUCKET'] } else { $env:SUPABASE_BUCKET }
if (-not $Bucket) { $Bucket = 'tourist-images' }

if (-not $SupabaseUrl) {
  Write-Error "Missing SUPABASE_URL. Create $EnvFile from .env.example"
}
if (-not $ServiceKey) {
  Write-Error "Missing SUPABASE_SERVICE_ROLE_KEY in $EnvFile (do not paste it in chat)."
}

$SupabaseUrl = $SupabaseUrl.TrimEnd('/')
$AssetsRoot = Join-Path $Root 'assets'
$Exts = @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp')

$files = @(Get-ChildItem -LiteralPath $AssetsRoot -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $Exts -contains $_.Extension.ToLowerInvariant() })

Write-Host "Uploading $($files.Count) files to bucket '$Bucket'..."
$ok = 0
$fail = 0
$i = 0

foreach ($file in $files) {
  $i++
  $rel = $file.FullName.Substring($AssetsRoot.Length).TrimStart([char]'\', [char]'/')
  $objectKey = ($rel -replace '\\', '/')
  # Sanitize Unicode that Supabase Storage rejects (accents, bullets, en-dash)
  $sanitized = New-Object System.Text.StringBuilder
  foreach ($ch in $objectKey.ToCharArray()) {
    $code = [int]$ch
    if ($ch -eq [char]0x2013 -or $ch -eq [char]0x2014 -or $ch -eq [char]0x2022) { [void]$sanitized.Append('-') }
    elseif ($code -eq 0x00E9 -or $code -eq 0x00E8 -or $code -eq 0x00EA) { [void]$sanitized.Append('e') }
    elseif ($code -eq 0x00C9 -or $code -eq 0x00C8 -or $code -eq 0x00CA) { [void]$sanitized.Append('E') }
    elseif ($code -gt 127) { [void]$sanitized.Append('x') }
    else { [void]$sanitized.Append($ch) }
  }
  $objectKey = $sanitized.ToString()
  $lower = $objectKey.ToLowerInvariant()
  if ($lower -like '*final logo*' -or $lower -like '*atmos_trs_brand_logo*' -or $lower -like '*tourism logo*') {
    Write-Host "[$i/$($files.Count)] SKIP local-only: $objectKey"
    continue
  }

  $encodedKey = ($objectKey.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
  $uri = "$SupabaseUrl/storage/v1/object/$Bucket/$encodedKey"

  $ext = $file.Extension.ToLowerInvariant()
  $contentType = switch ($ext) {
    '.png' { 'image/png' }
    '.jpg' { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.webp' { 'image/webp' }
    '.gif' { 'image/gif' }
    '.bmp' { 'image/bmp' }
    default { 'application/octet-stream' }
  }

  $headers = @{
    Authorization = "Bearer $ServiceKey"
    apikey        = $ServiceKey
    'x-upsert'    = 'true'
  }

  try {
    Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -InFile $file.FullName -ContentType $contentType | Out-Null
    $ok++
    if (($i % 10 -eq 0) -or ($i -eq $files.Count)) {
      Write-Host "[$i/$($files.Count)] OK $objectKey"
    }
  }
  catch {
    $fail++
    $msg = $_.Exception.Message
    Write-Host "[$i/$($files.Count)] FAIL $objectKey - $msg"
  }
}

Write-Host ""
Write-Host "Done. uploaded=$ok failed=$fail"
$publicBase = "$SupabaseUrl/storage/v1/object/public/$Bucket/"
Write-Host "Public base: $publicBase"
