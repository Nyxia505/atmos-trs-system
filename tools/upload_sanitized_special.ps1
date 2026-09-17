# Upload the 7 InvalidKey files using ASCII-sanitized object keys.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root '.env'

function Read-DotEnv([string]$Path) {
  $map = @{}
  Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { return }
    $i = $line.IndexOf('=')
    if ($i -lt 1) { return }
    $map[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim().Trim('"').Trim("'")
  }
  return $map
}

function Sanitize-ObjectKey([string]$Key) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $Key.ToCharArray()) {
    $code = [int]$ch
    if ($ch -eq [char]0x2013 -or $ch -eq [char]0x2014 -or $ch -eq [char]0x2022) {
      [void]$sb.Append('-')
    }
    elseif ($code -gt 127) {
      # Basic Latin accent fold for common French chars
      switch ($ch) {
        ([char]0x00E9) { [void]$sb.Append('e') } # e acute
        ([char]0x00E8) { [void]$sb.Append('e') } # e grave
        ([char]0x00EA) { [void]$sb.Append('e') }
        ([char]0x00E0) { [void]$sb.Append('a') }
        ([char]0x00F1) { [void]$sb.Append('n') }
        ([char]0x00FC) { [void]$sb.Append('u') }
        default { [void]$sb.Append('x') }
      }
    }
    else {
      [void]$sb.Append($ch)
    }
  }
  return $sb.ToString()
}

$envMap = Read-DotEnv $EnvFile
$SupabaseUrl = $envMap['SUPABASE_URL'].TrimEnd('/')
$ServiceKey = $envMap['SUPABASE_SERVICE_ROLE_KEY']
$Bucket = if ($envMap['SUPABASE_BUCKET']) { $envMap['SUPABASE_BUCKET'] } else { 'tourist-images' }
$AssetsRoot = Join-Path $Root 'assets'
$Exts = @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp')

$files = @(Get-ChildItem -LiteralPath $AssetsRoot -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $Exts -contains $_.Extension.ToLowerInvariant() } |
  Where-Object {
    $rel = $_.FullName.Substring($AssetsRoot.Length).TrimStart([char]'\', [char]'/')
    $objectKey = ($rel -replace '\\', '/')
    ($objectKey.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -gt 0
  })

Write-Host "Uploading $($files.Count) sanitized keys..."
$ok = 0
$fail = 0

foreach ($file in $files) {
  $rel = $file.FullName.Substring($AssetsRoot.Length).TrimStart([char]'\', [char]'/')
  $objectKey = Sanitize-ObjectKey (($rel -replace '\\', '/'))
  $encodedKey = ($objectKey.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
  $uri = "$SupabaseUrl/storage/v1/object/$Bucket/$encodedKey"
  $ext = $file.Extension.ToLowerInvariant()
  $contentType = switch ($ext) {
    '.png' { 'image/png' }
    '.jpg' { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.webp' { 'image/webp' }
    default { 'application/octet-stream' }
  }

  try {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $req = [System.Net.HttpWebRequest]::Create($uri)
    $req.Method = 'POST'
    $req.ContentType = $contentType
    $req.Headers.Add('Authorization', "Bearer $ServiceKey")
    $req.Headers.Add('apikey', $ServiceKey)
    $req.Headers.Add('x-upsert', 'true')
    $req.ContentLength = $bytes.Length
    $stream = $req.GetRequestStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()
    $resp = $req.GetResponse()
    $resp.Close()
    $ok++
    Write-Host "OK -> $objectKey"
  }
  catch {
    $fail++
    Write-Host "FAIL $objectKey - $($_.Exception.Message)"
  }
}

Write-Host "done ok=$ok fail=$fail"
