# Retry uploads for files whose relative paths contain non-ASCII characters.
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
    ($objectKey.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -gt 0 -or $objectKey -like '*Zipline*'
  })

Write-Host "Retrying $($files.Count) special files..."
$ok = 0
$fail = 0

foreach ($file in $files) {
  $rel = $file.FullName.Substring($AssetsRoot.Length).TrimStart([char]'\', [char]'/')
  $objectKey = ($rel -replace '\\', '/')
  $encodedKey = ($objectKey.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
  $uri = "$SupabaseUrl/storage/v1/object/$Bucket/$encodedKey"

  $ext = $file.Extension.ToLowerInvariant()
  $contentType = switch ($ext) {
    '.png' { 'image/png' }
    '.jpg' { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.webp' { 'image/webp' }
    '.gif' { 'image/gif' }
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
    Write-Host "OK $objectKey"
  }
  catch {
    $fail++
    $msg = $_.Exception.Message
    if ($_.Exception.InnerException) { $msg = $_.Exception.InnerException.Message }
    # Try to read HTTP error body
    try {
      $wr = $_.Exception.Response
      if ($null -eq $wr -and $_.Exception.InnerException) { $wr = $_.Exception.InnerException.Response }
      if ($wr -ne $null) {
        $reader = New-Object System.IO.StreamReader($wr.GetResponseStream())
        $body = $reader.ReadToEnd()
        $reader.Close()
        $msg = "$msg | $body"
      }
    } catch {}
    Write-Host "FAIL $objectKey - $msg"
  }
}

Write-Host "done ok=$ok fail=$fail"
