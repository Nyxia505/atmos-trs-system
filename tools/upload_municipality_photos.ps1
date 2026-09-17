# Upload per-LGU municipality photos to Supabase Storage.
#
# Source files stay where they are under assets/images/ (no local duplication);
# only the destination object key is renamed to the canonical
# municipalities/<lguId>/<lowercase_name> layout.
#
# Requires project-root .env with SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
# SUPABASE_BUCKET (see .env.example).

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
    $map[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1).Trim().Trim('"').Trim("'")
  }
  return $map
}

$envMap = Read-DotEnv $EnvFile
$SupabaseUrl = if ($envMap['SUPABASE_URL']) { $envMap['SUPABASE_URL'] } else { $env:SUPABASE_URL }
$ServiceKey = if ($envMap['SUPABASE_SERVICE_ROLE_KEY']) { $envMap['SUPABASE_SERVICE_ROLE_KEY'] } else { $env:SUPABASE_SERVICE_ROLE_KEY }
$Bucket = if ($envMap['SUPABASE_BUCKET']) { $envMap['SUPABASE_BUCKET'] } else { 'tourist-images' }

if (-not $SupabaseUrl) { Write-Error "Missing SUPABASE_URL. Create $EnvFile from .env.example" }
if (-not $ServiceKey) { Write-Error "Missing SUPABASE_SERVICE_ROLE_KEY in $EnvFile (do not paste it in chat)." }

$SupabaseUrl = $SupabaseUrl.TrimEnd('/')

# source path under assets/  ->  object key under municipalities/
$Uploads = [ordered]@{
  'images/oroquieta City plaza.jpeg'                  = 'oroquieta/oroquieta_city_plaza.jpeg'
  'images/lgu/oroquieta_plaza_hero.png'               = 'oroquieta/oroquieta_plaza_hero.png'
  'images/capitol.webp'                               = 'oroquieta/oroquieta_capitol.webp'
  'images/ozamis city.webp'                           = 'ozamiz/ozamiz_city.webp'
  'images/Cotta Fort & Shrine.jpg'                    = 'ozamiz/ozamiz_cotta_fort_shrine.jpg'
  'images/Immaculate Conception Cathedral.webp'       = 'ozamiz/ozamiz_immaculate_conception_cathedral.webp'
  'images/Cotta Beach.jpg'                            = 'ozamiz/ozamiz_cotta_beach.jpg'
  'images/Asenso Global Garden 1.png'                 = 'tangub/tangub_asenso_global_garden.png'
  'images/lgu/tangub_promo.png'                       = 'tangub/tangub_promo.png'
  'images/aloran.png'                                 = 'aloran/aloran.png'
  'images/Baliangao.png'                              = 'baliangao/baliangao.png'
  'images/Sunrise Beach Baliangao.jpg'                = 'baliangao/baliangao_sunrise_beach.jpg'
  'images/baliangao_protected_landscape_seascape.png' = 'baliangao/baliangao_protected_landscape_seascape.png'
  'images/Bonifacio_kanao.png'                        = 'bonifacio/bonifacio_kanao.png'
  'images/Calamba.png'                                = 'calamba/calamba.png'
  'images/Clarin.png'                                 = 'clarin/clarin.png'
  'images/lake_duminagat.webp'                        = 'clarin/clarin_lake_duminagat.webp'
  'images/conception_v2.png'                          = 'concepcion/conception_v2.png'
  'images/DonVic_v2.png'                              = 'dvc/donvic_v2.png'
  'images/Jimenez.png'                                = 'jimenez/jimenez.png'
  'images/Lopez Jaena.png'                            = 'lopezjaena/lopezjaena.png'
  'images/Panaon.png'                                 = 'panaon/panaon.png'
  'images/Plaridel.png'                               = 'plaridel/plaridel.png'
  'images/Sapang_Dalaga_v2.png'                       = 'sapangdalaga/sapang_dalaga_v2.png'
  'images/Amorap.png'                                 = 'sinacaban/sinacaban_amorap.png'
  'images/Tudela Village.webp'                        = 'tudela/tudela_village.webp'
}

$AssetsRoot = Join-Path $Root 'assets'
$headers = @{
  Authorization = "Bearer $ServiceKey"
  apikey        = $ServiceKey
  'x-upsert'    = 'true'
}

Write-Host "Uploading $($Uploads.Count) municipality photos to '$Bucket'..."
$ok = 0
$fail = 0
$i = 0

foreach ($entry in $Uploads.GetEnumerator()) {
  $i++
  $source = Join-Path $AssetsRoot ($entry.Key -replace '/', '\')
  $objectKey = "municipalities/$($entry.Value)"

  if (-not (Test-Path -LiteralPath $source)) {
    $fail++
    Write-Host "[$i/$($Uploads.Count)] MISSING source: $($entry.Key)"
    continue
  }

  $contentType = switch ([IO.Path]::GetExtension($source).ToLowerInvariant()) {
    '.png' { 'image/png' }
    '.jpg' { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.webp' { 'image/webp' }
    default { 'application/octet-stream' }
  }

  $encodedKey = ($objectKey.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
  $uri = "$SupabaseUrl/storage/v1/object/$Bucket/$encodedKey"

  try {
    Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -InFile $source -ContentType $contentType | Out-Null
    $ok++
    Write-Host "[$i/$($Uploads.Count)] OK   $objectKey"
  }
  catch {
    $fail++
    Write-Host "[$i/$($Uploads.Count)] FAIL $objectKey - $($_.Exception.Message)"
  }
}

Write-Host ""
Write-Host "Done. uploaded=$ok failed=$fail"
Write-Host "Public base: $SupabaseUrl/storage/v1/object/public/$Bucket/municipalities/"
