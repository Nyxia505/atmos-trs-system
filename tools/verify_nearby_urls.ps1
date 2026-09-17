$ErrorActionPreference = 'Continue'
$content = Get-Content -LiteralPath 'lib\data\featured_destinations.dart' -Raw
$matches = [regex]::Matches($content, "assets/municipalities/[^'""\s]+/nearby/[^'""\s]+")
$paths = $matches | ForEach-Object { $_.Value } | Sort-Object -Unique
$base = 'https://cgpjqkbbmyxvitwpkikn.supabase.co/storage/v1/object/public/tourist-images/'
$bad = 0
foreach ($p in $paths) {
  $key = $p.Substring('assets/'.Length)
  $u = $base + (($key.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
  try {
    $r = Invoke-WebRequest -UseBasicParsing -Method Head -Uri $u -TimeoutSec 30
    if ($r.StatusCode -ne 200) {
      $bad++
      Write-Host "$($r.StatusCode) $key"
    }
  }
  catch {
    $bad++
    Write-Host "FAIL $key"
  }
}
Write-Host "unique=$($paths.Count) not_ok=$bad"
