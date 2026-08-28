/**
 * Sync tourist_spots image_url / image fields from the bundled asset catalog.
 *
 * Usage (from repo root, with a service account or GOOGLE_APPLICATION_CREDENTIALS):
 *   node tools/sync_tourist_spot_images.js
 */
const admin = require('firebase-admin');

const SPOT_IMAGES = {
  oroquieta_city_boulevard_and_peoples_park: 'assets/images/oroquieta City plaza.jpeg',
  oroquieta_city_plaza: 'assets/images/oroquieta City plaza.jpeg',
  ozamiz_asenso_wellness_park: 'assets/images/ozamis city.webp',
  ozamiz_cotta_fort_shrine: "assets/images/Cotta Fort & Shrine.jpg",
  ozamiz_immaculate_conception_cathedral:
    'assets/images/Immaculate Conception Cathedral.webp',
  ozamiz_cotta_beach: 'assets/images/Cotta Beach.jpg',
  ozamiz_cotta_fort_wellness_park: "assets/images/Cotta Fort & Shrine.jpg",
  tangub_asenso_global_gardens: 'assets/images/Asenso Global Garden 1.png',
  aloran_viewpoint: 'assets/images/aloran.jpg',
  bless_amare_sunrise_beach: 'assets/images/Baliangao - Cabgan Island.jpg',
  baliangao_protected_landscape: 'assets/images/Baliangao - Cabgan Island.jpg',
  calamba_green_hills: 'assets/images/Calamba.jpg',
  clarin_lake_duminagat: 'assets/images/lake_duminagat.webp',
  concepcion_falls: 'assets/images/conception.png',
  dvc_mount_malindang_natural_park: 'assets/images/Piduan Falls Donvic.jpg',
  jimenez_st_john_the_baptist_church:
    'assets/images/Jimenez - St. John the Baptist Church.jpg',
  lopez_jaena_beachfront: 'assets/images/Lopez Jaena.jpg',
  panaon_seaside: 'assets/images/Panaon.png',
  plaridel_resort: 'assets/images/PLARIDEL.jpg',
  sapang_dalaga_floating_cottages: 'assets/images/Sapang Dalaga.png',
  sinacaban_asenso_aquamarine_park: 'assets/images/AMORAP.jpg',
  tudela_highland_resort_eco_park: 'assets/images/Tudela Village.webp',
  el_triungo_beach: 'assets/images/el triunfo.png',
  el_triunfo_beach: 'assets/images/el triunfo.png',
  piduan_falls: 'assets/images/Piduan Falls Donvic.jpg',
  misocc_capitol: 'assets/images/capitol.webp',
  lumantas_riverside: 'assets/images/lumantas river side garden.webp',
  triplan_hub: 'assets/images/tripplan.png',
};

const MUNICIPALITY_IMAGES = {
  oroquieta: 'assets/images/oroquieta City plaza.jpeg',
  ozamiz: 'assets/images/ozamis city.webp',
  ozamis: 'assets/images/ozamis city.webp',
  tangub: 'assets/images/Asenso Global Garden 1.png',
  aloran: 'assets/images/aloran.jpg',
  clarin: 'assets/images/clarin.jpg',
  baliangao: 'assets/images/Baliangao - Cabgan Island.jpg',
  sapang_dalaga: 'assets/images/Sapang Dalaga.png',
  sapangdalaga: 'assets/images/Sapang Dalaga.png',
  dvc: 'assets/images/Piduan Falls Donvic.jpg',
  jimenez: 'assets/images/Jimenez - St. John the Baptist Church.jpg',
  calamba: 'assets/images/Calamba.jpg',
  concepcion: 'assets/images/conception.png',
  plaridel: 'assets/images/PLARIDEL.jpg',
  sinacaban: 'assets/images/AMORAP.jpg',
  tudela: 'assets/images/Tudela Village.webp',
  panaon: 'assets/images/Panaon.png',
  lopezjaena: 'assets/images/Lopez Jaena.jpg',
};

function resolveImage(docId, data) {
  if (SPOT_IMAGES[docId]) return SPOT_IMAGES[docId];
  const mid = (data.municipalityId || '').trim().toLowerCase();
  if (MUNICIPALITY_IMAGES[mid]) return MUNICIPALITY_IMAGES[mid];
  return null;
}

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  const db = admin.firestore();
  const snap = await db.collection('tourist_spots').get();
  let updated = 0;
  let skipped = 0;
  let missing = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const existing = (data.image_url || data.image || '').trim();
    const resolved = resolveImage(doc.id, data);
    if (!resolved) {
      missing++;
      continue;
    }
    if (existing === resolved) {
      skipped++;
      continue;
    }
    await doc.ref.set(
      {image_url: resolved, image: resolved},
      {merge: true},
    );
    updated++;
    console.log(`Updated ${doc.id} -> ${resolved}`);
  }

  console.log(
    `Done. updated=${updated} skipped=${skipped} missing=${missing} total=${snap.size}`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
