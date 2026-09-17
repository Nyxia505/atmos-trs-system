# Upload nearby hotel / cafe / restaurant / attraction photos into
# municipalities/<lguId>/nearby/<category>/ on the tourist-images bucket.
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

# source under assets/  ->  object key under municipalities/
$Uploads = [ordered]@{
  # --- baliangao ---
  'images/Camp Sawi.jpg' = 'baliangao/nearby/restaurants/camp_sawi.jpg'
  "images/Nami's.jpg" = 'baliangao/nearby/restaurants/namis.jpg'
  "Nearby Hotel's in Sunrise Beach/ANTELMI TRAVELERS INN.webp" = 'baliangao/nearby/hotels/antelmi_travelers_inn.webp'
  "Nearby Hotel's in Sunrise Beach/Hotel Bijoux.webp" = 'baliangao/nearby/hotels/hotel_bijoux.webp'
  "Nearby Hotel's in Sunrise Beach/D&M Travellers Inn.jpg" = 'baliangao/nearby/hotels/dm_travellers_inn.jpg'
  "Nearby Hotel's in Sunrise Beach/Daydream Ranch Resort.jpg" = 'baliangao/nearby/hotels/daydream_ranch_resort.jpg'
  'images/Baliangao - Cabgan Island.jpg' = 'baliangao/nearby/attractions/cabgan_island.jpg'
  'images/baliangao_protected_landscape_seascape.png' = 'baliangao/nearby/attractions/protected_landscape_seascape.png'
  'images/jabiens_integrated_farm.png' = 'baliangao/nearby/attractions/jabiens_integrated_farm.png'
  'images/casa_antonio_resort.png' = 'baliangao/nearby/attractions/casa_antonio_resort.png'
  'images/bito_on_beach_resort.png' = 'baliangao/nearby/attractions/bito_on_beach_resort.png'
  'images/cup_of_grace.png' = 'baliangao/nearby/cafes/cup_of_grace.png'
  'images/lei_brew.png' = 'baliangao/nearby/cafes/lei_brew.png'
  'images/trinas_kapehan.png' = 'baliangao/nearby/cafes/trinas_kapehan.png'

  # --- ozamiz restaurants ---
  'ozamiz nearby/restaurants/Cribs Diner oz.jpg' = 'ozamiz/nearby/restaurants/cribs_diner.jpg'
  'ozamiz nearby/restaurants/Rodolfos Ozamiz.jpg' = 'ozamiz/nearby/restaurants/rodolfos.jpg'
  'ozamiz nearby/restaurants/Banyan Resto.jpg' = 'ozamiz/nearby/restaurants/banyan_resto.jpg'
  'ozamiz nearby/restaurants/Isla Cafe and Restaurant.jpg' = 'ozamiz/nearby/restaurants/isla_cafe_and_restaurant.jpg'
  'ozamiz nearby/restaurants/Puesto.jpg' = 'ozamiz/nearby/restaurants/puesto.jpg'
  "ozamiz nearby/restaurants/Gat's Bar.jpg" = 'ozamiz/nearby/restaurants/gats_bar.jpg'
  'ozamiz nearby/restaurants/Villatuna - Ozamiz City.jpg' = 'ozamiz/nearby/restaurants/villatuna.jpg'
  'ozamiz nearby/restaurants/Blue Note Music Lounge.jpg' = 'ozamiz/nearby/restaurants/blue_note_music_lounge.jpg'
  'ozamiz nearby/restaurants/Kinuman Restaurant.webp' = 'ozamiz/nearby/restaurants/kinuman_restaurant.webp'
  'ozamiz nearby/restaurants/PANTAWAN RESTAURANT.jpg' = 'ozamiz/nearby/restaurants/pantawan_restaurant.jpg'
  'ozamiz nearby/restaurants/Très Coffee Company.jpg' = 'ozamiz/nearby/restaurants/tres_coffee_company.jpg'
  'ozamiz nearby/restaurants/Better Brews - Ozamiz City.jpg' = 'ozamiz/nearby/restaurants/better_brews.jpg'
  'ozamiz nearby/restaurants/Grill Champ.jpg' = 'ozamiz/nearby/restaurants/grill_champ.jpg'
  'ozamiz nearby/restaurants/Gee Grill.jpg' = 'ozamiz/nearby/restaurants/gee_grill.jpg'
  'ozamiz nearby/restaurants/Raan•Day•Vu Cafe.jpg' = 'ozamiz/nearby/restaurants/raan_day_vu_cafe.jpg'
  'ozamiz nearby/restaurants/Le Bistro.jpg' = 'ozamiz/nearby/restaurants/le_bistro.jpg'
  "ozamiz nearby/restaurants/Foodie's Corner.jpg" = 'ozamiz/nearby/restaurants/foodies_corner.jpg'
  'ozamiz nearby/restaurants/Conrads Restobar.jpg' = 'ozamiz/nearby/restaurants/conrads_restobar.jpg'
  'ozamiz nearby/restaurants/Chicken Ati-Atihan.jpg' = 'ozamiz/nearby/restaurants/chicken_ati_atihan.jpg'
  'ozamiz nearby/restaurants/NM Gohantoboru Japanese Restaurant.webp' = 'ozamiz/nearby/restaurants/nm_gohantoboru.webp'

  # --- ozamiz hotels ---
  'ozamiz nearby/royal garden hotel/royal.jpeg' = 'ozamiz/nearby/hotels/royal_garden_hotel.jpeg'
  'ozamiz nearby/royal garden hotel/52469423.jpg' = 'ozamiz/nearby/hotels/royal_garden_hotel_02.jpg'
  'ozamiz nearby/royal garden hotel/52469425.jpg' = 'ozamiz/nearby/hotels/royal_garden_hotel_03.jpg'
  'ozamiz nearby/royal garden hotel/52469431.jpg' = 'ozamiz/nearby/hotels/royal_garden_hotel_04.jpg'
  'ozamiz nearby/royal garden hotel/52469444.jpg' = 'ozamiz/nearby/hotels/royal_garden_hotel_05.jpg'
  'ozamiz nearby/royal garden hotel/20b9378e1918c1395d7f3da051bae559.webp' = 'ozamiz/nearby/hotels/royal_garden_hotel_06.webp'
  'ozamiz nearby/royal garden hotel/2fba8a3548759a1ba79318c9439d69db.webp' = 'ozamiz/nearby/hotels/royal_garden_hotel_07.webp'
  'ozamiz nearby/royal garden hotel/ec5ecc4e2cf2a971baf75d8f517b2a16.webp' = 'ozamiz/nearby/hotels/royal_garden_hotel_08.webp'
  'ozamiz nearby/royal garden hotel/f581ca13e703a08f0ec5bd9211802e06.webp' = 'ozamiz/nearby/hotels/royal_garden_hotel_09.webp'
  'ozamiz nearby/AVISHA HOTEL.jpg' = 'ozamiz/nearby/hotels/avisha_hotel.jpg'
  'ozamiz nearby/Boutique Hotel.jpg' = 'ozamiz/nearby/hotels/boutique_hotel.jpg'
  'ozamiz nearby/Executive Hotel.jpg' = 'ozamiz/nearby/hotels/executive_hotel.jpg'
  'ozamiz nearby/GV hotel.jpg' = 'ozamiz/nearby/hotels/gv_hotel.jpg'
  'ozamiz nearby/Mt. Moriah Inn.jpg' = 'ozamiz/nearby/hotels/mt_moriah_inn.jpg'
  'ozamiz nearby/Oakhill Inn.webp' = 'ozamiz/nearby/hotels/oakhill_inn.webp'

  # --- ozamiz cafes ---
  "ozamiz nearby/coffee's/813 - Eight Thirteen Café.png" = 'ozamiz/nearby/cafes/eight_thirteen_cafe.png'
  "ozamiz nearby/coffee's/iKao Café.webp" = 'ozamiz/nearby/cafes/ikao_cafe.webp'
  "ozamiz nearby/coffee's/Occidental Kape and Pan.jpg" = 'ozamiz/nearby/cafes/occidental_kape_and_pan.jpg'
  "ozamiz nearby/coffee's/Raan•Day•Vu - Ablaze 2.0.webp" = 'ozamiz/nearby/cafes/raan_day_vu_ablaze.webp'
  "ozamiz nearby/coffee's/Raan•Day•Vu Cafe.jpg" = 'ozamiz/nearby/cafes/raan_day_vu_cafe.jpg'
  "ozamiz nearby/coffee's/Terry&Perry Coffee - Ozamiz.webp" = 'ozamiz/nearby/cafes/terry_and_perry_coffee.webp'

  # --- ozamiz attractions ---
  'images/Cotta Fort & Shrine.jpg' = 'ozamiz/nearby/attractions/cotta_fort_shrine.jpg'
  'images/Immaculate Conception Cathedral.webp' = 'ozamiz/nearby/attractions/immaculate_conception_cathedral.webp'
  'images/Cotta Beach.jpg' = 'ozamiz/nearby/attractions/cotta_beach.jpg'

  # --- tangub ---
  'images/nearby/tangub_domings_restaurant.png' = 'tangub/nearby/restaurants/domings_restaurant.png'
  'images/nearby/tangub_d_hermanos.png' = 'tangub/nearby/restaurants/d_hermanos.png'
  'images/nearby/tangub_purple_haus.png' = 'tangub/nearby/restaurants/purple_haus.png'
  'images/nearby/tangub_sordillas.png' = 'tangub/nearby/restaurants/sordillas.png'
  'images/nearby/tangub_domings.png' = 'tangub/nearby/restaurants/domings.png'
  'images/nearby/tangub_elvas_house.png' = 'tangub/nearby/hotels/elvas_house.png'
  'images/nearby/tangub_asenso_global_garden.png' = 'tangub/nearby/attractions/asenso_global_garden.png'
  'images/nearby/tangub_camp_sawi.png' = 'tangub/nearby/attractions/camp_sawi.png'

  # --- jimenez ---
  'images/nearby/jimenez_alfredo_seafood.png' = 'jimenez/nearby/restaurants/alfredo_seafood.png'
  'images/nearby/jimenez_casa_bacarro.png' = 'jimenez/nearby/restaurants/casa_bacarro.png'
  'images/nearby/jimenez_casa_bacarro_2.png' = 'jimenez/nearby/restaurants/casa_bacarro_2.png'
  'images/nearby/jimenez_lil_cezar.png' = 'jimenez/nearby/restaurants/lil_cezar.png'
  'images/nearby/jimenez_shanghai_noodle.png' = 'jimenez/nearby/restaurants/shanghai_noodle.png'
  'images/nearby/jimenez_sidewok.png' = 'jimenez/nearby/restaurants/sidewok.png'
  'images/nearby/jimenez_baroto_glampgrounds.png' = 'jimenez/nearby/hotels/baroto_glampgrounds.png'

  # --- oroquieta restaurants (coffee-shop folder sources, restaurant list) ---
  'oroquieta city nearby/nearby coffee shop/mons gril.webp' = 'oroquieta/nearby/restaurants/mons_grill.webp'
  'oroquieta city nearby/nearby coffee shop/better brews_.webp' = 'oroquieta/nearby/restaurants/better_brews.webp'
  'oroquieta city nearby/nearby coffee shop/Bella_s Cafe.webp' = 'oroquieta/nearby/restaurants/bellas_cafe.webp'
  'oroquieta city nearby/nearby coffee shop/Cucina Luciano.webp' = 'oroquieta/nearby/restaurants/cucina_luciano.webp'
  'oroquieta city nearby/nearby coffee shop/gorge cafe.webp' = 'oroquieta/nearby/restaurants/gorge_cafe.webp'
  'oroquieta city nearby/nearby coffee shop/the waisted chef.webp' = 'oroquieta/nearby/restaurants/the_waisted_chef.webp'
  'oroquieta city nearby/nearby coffee shop/chopsticks_.webp' = 'oroquieta/nearby/restaurants/chopsticks.webp'
  'oroquieta city nearby/nearby coffee shop/A+ coffee corner.webp' = 'oroquieta/nearby/restaurants/a_plus_coffee_corner.webp'
  'oroquieta city nearby/nearby coffee shop/penny lane cafe.webp' = 'oroquieta/nearby/restaurants/penny_lane_cafe.webp'
  'oroquieta city nearby/nearby coffee shop/cafe yek.jpg' = 'oroquieta/nearby/restaurants/cafe_yek.jpg'
  'oroquieta city nearby/nearby coffee shop/uma.jpg' = 'oroquieta/nearby/restaurants/uma_cafe.jpg'

  # --- oroquieta hotels ---
  'oroquieta city nearby/hotel/Agricio Farm and Resort.webp' = 'oroquieta/nearby/hotels/agricio_farm_and_resort.webp'
  'oroquieta city nearby/hotel/Kenjelo.webp' = 'oroquieta/nearby/hotels/kenjelo.webp'
  'oroquieta city nearby/hotel/Almar Suites.webp' = 'oroquieta/nearby/hotels/almar_suites.webp'
  'oroquieta city nearby/hotel/costa del sol.webp' = 'oroquieta/nearby/hotels/costa_del_sol.webp'
  'oroquieta city nearby/hotel/sheena_s hotel.webp' = 'oroquieta/nearby/hotels/sheenas_hotel.webp'
  'oroquieta city nearby/hotel/Daminar River Side Garden).webp' = 'oroquieta/nearby/hotels/daminar_riverside_garden.webp'
  'oroquieta city nearby/hotel/novo hotel.webp' = 'oroquieta/nearby/hotels/novo_hotel.webp'

  # --- oroquieta attractions ---
  'oroquieta city nearby/Tourist Attractions/Ambak-Ambak Falls.jpeg' = 'oroquieta/nearby/attractions/ambak_ambak_falls.jpeg'
  'oroquieta city nearby/Tourist Attractions/Ciriaco Pastrano Hanging Footbridge.jpeg' = 'oroquieta/nearby/attractions/ciriaco_pastrano_hanging_footbridge.jpeg'
  'oroquieta city nearby/Tourist Attractions/Isko Resort.jpeg' = 'oroquieta/nearby/attractions/isko_resort.jpeg'
  'oroquieta city nearby/Tourist Attractions/Libadatama Dam (City Dam) or Layawan River.jpeg' = 'oroquieta/nearby/attractions/libadatama_dam_layawan_river.jpeg'
  'oroquieta city nearby/Tourist Attractions/Mobod Fish Sanctuary.jpeg' = 'oroquieta/nearby/attractions/mobod_fish_sanctuary.jpeg'
  'oroquieta city nearby/Tourist Attractions/Oro Zipline – Oroquieta City.jpeg' = 'oroquieta/nearby/attractions/oro_zipline.jpeg'
  'oroquieta city nearby/Tourist Attractions/Pamana Nature Camping Resort.webp' = 'oroquieta/nearby/attractions/pamana_nature_camping_resort.webp'
  'oroquieta city nearby/Tourist Attractions/Sibucal Hot Springs.webp' = 'oroquieta/nearby/attractions/sibucal_hot_springs.webp'

  # --- sinacaban ---
  'images/nearby/sinacaban_palayan_seafood.webp' = 'sinacaban/nearby/restaurants/palayan_seafood.webp'
  'images/nearby/sinacaban_yobab_konam.png' = 'sinacaban/nearby/restaurants/yobab_konam.png'
  'images/nearby/sinacaban_la_elena_aquapark.webp' = 'sinacaban/nearby/restaurants/la_elena_aquapark.webp'
  'images/nearby/sinacaban_hg_glomax_inn.webp' = 'sinacaban/nearby/hotels/hg_glomax_inn.webp'
  'images/nearby/sinacaban_beach_resort.webp' = 'sinacaban/nearby/hotels/beach_resort.webp'
  'images/nearby/sinacaban_sungan_mountain.webp' = 'sinacaban/nearby/hotels/sungan_mountain.webp'
  'images/nearby/sinacaban_pavilion.webp' = 'sinacaban/nearby/hotels/pavilion.webp'
  'images/nearby/sinacaban_busay_tipan_falls.webp' = 'sinacaban/nearby/attractions/busay_tipan_falls.webp'
}

# Ordered hashtable overwrites duplicate keys — re-add cafe destinations that share
# restaurant sources by uploading them explicitly after the loop if needed.
# PowerShell ordered hashtables: later assignment of same key overwrites.
# Fix: use unique destination keys; for shared sources that need two dests,
# list restaurants first then cafes with different dest keys — but same source
# key in hashtable can only appear once. So cafes that share restaurant sources
# must be uploaded in a second pass.

$CafeShared = [ordered]@{
  'oroquieta city nearby/nearby coffee shop/A+ coffee corner.webp' = 'oroquieta/nearby/cafes/a_plus_coffee_corner.webp'
  'oroquieta city nearby/nearby coffee shop/better brews_.webp' = 'oroquieta/nearby/cafes/better_brews.webp'
  'oroquieta city nearby/nearby coffee shop/chopsticks_.webp' = 'oroquieta/nearby/cafes/chopsticks.webp'
  'oroquieta city nearby/nearby coffee shop/Cucina Luciano.webp' = 'oroquieta/nearby/cafes/cucina_luciano.webp'
  'oroquieta city nearby/nearby coffee shop/gorge cafe.webp' = 'oroquieta/nearby/cafes/gorge_cafe.webp'
  'oroquieta city nearby/nearby coffee shop/mons gril.webp' = 'oroquieta/nearby/cafes/mons_grill.webp'
  'oroquieta city nearby/nearby coffee shop/penny lane cafe.webp' = 'oroquieta/nearby/cafes/penny_lane_cafe.webp'
  'oroquieta city nearby/nearby coffee shop/the waisted chef.webp' = 'oroquieta/nearby/cafes/the_waisted_chef.webp'
  'oroquieta city nearby/nearby coffee shop/cafe yek.jpg' = 'oroquieta/nearby/cafes/cafe_yek.jpg'
  'oroquieta city nearby/nearby coffee shop/uma.jpg' = 'oroquieta/nearby/cafes/uma_cafe.jpg'
}

# Remove cafe-only entries that were overwritten out of $Uploads by restaurant keys;
# keep Bella Cafe _.webp which is unique to cafes.
$Uploads['oroquieta city nearby/nearby coffee shop/Bella_s Cafe_.webp'] = 'oroquieta/nearby/cafes/bellas_cafe.webp'

$AssetsRoot = Join-Path $Root 'assets'
$headers = @{
  Authorization = "Bearer $ServiceKey"
  apikey        = $ServiceKey
  'x-upsert'    = 'true'
}

function Upload-One([string]$SourceRel, [string]$DestRel) {
  $source = Join-Path $AssetsRoot ($SourceRel -replace '/', '\')
  $objectKey = "municipalities/$DestRel"
  if (-not (Test-Path -LiteralPath $source)) {
    return @{ ok = $false; msg = "MISSING $SourceRel" }
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
    return @{ ok = $true; msg = $objectKey }
  }
  catch {
    return @{ ok = $false; msg = "$objectKey - $($_.Exception.Message)" }
  }
}

$all = New-Object System.Collections.Generic.List[object]
foreach ($e in $Uploads.GetEnumerator()) {
  $all.Add([pscustomobject]@{ Source = $e.Key; Dest = $e.Value })
}
foreach ($e in $CafeShared.GetEnumerator()) {
  $all.Add([pscustomobject]@{ Source = $e.Key; Dest = $e.Value })
}

# Deduplicate by Dest
$seen = @{}
$unique = New-Object System.Collections.Generic.List[object]
foreach ($item in $all) {
  if ($seen.ContainsKey($item.Dest)) { continue }
  $seen[$item.Dest] = $true
  $unique.Add($item)
}

Write-Host "Uploading $($unique.Count) nearby photos to '$Bucket'..."
$ok = 0
$fail = 0
$i = 0
foreach ($item in $unique) {
  $i++
  $result = Upload-One $item.Source $item.Dest
  if ($result.ok) {
    $ok++
    Write-Host "[$i/$($unique.Count)] OK   $($result.msg)"
  }
  else {
    $fail++
    Write-Host "[$i/$($unique.Count)] FAIL $($result.msg)"
  }
}

Write-Host ""
Write-Host "Done. uploaded=$ok failed=$fail"
Write-Host "Public base: $SupabaseUrl/storage/v1/object/public/$Bucket/municipalities/"
