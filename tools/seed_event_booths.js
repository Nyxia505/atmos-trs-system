/**
 * Creates event booth spots (one unique check-in QR each) for a booth
 * visit-count test: Oroquieta City Plaza Clusters 1-5 + USTP booth.
 *
 * Booths have NO latitude/longitude, so QR scans skip the GPS geofence and
 * work from anywhere. LGU Analytics "Most visited spots" ranks them by name.
 * Print the QR codes from LGU dashboard > Spot QR Codes (PDF / PNG per booth).
 *
 * Usage (repo root):
 *   node tools/seed_event_booths.js                    # dry run
 *   node tools/seed_event_booths.js --apply            # create / update booths
 *   node tools/seed_event_booths.js --remove --apply   # delete tagged booths
 */

const {initAdmin} = require('./lib/admin_cli_credential');

const EVENT_TAG = 'booth_test_2026_10';
const CATEGORY = 'Event Booth';
const CHECK_IN_BASE_URL = 'https://atmos-trs-system.web.app/checkin';
const ANCHOR_SPOT_NAME = 'Oroquieta City Plaza';

const BOOTHS = [
  ...Array.from({length: 5}, (_, i) => ({
    id: `oroquieta_plaza_cluster_${i + 1}`,
    name: `Oroquieta City Plaza - Cluster ${i + 1}`,
  })),
  {id: 'oroquieta_ustp_booth', name: 'USTP Booth'},
];

const args = new Set(process.argv.slice(2));
const apply = args.has('--apply');
const remove = args.has('--remove');

const WRITE_TIMEOUT_MS = 30000;

/** firebase-admin retries RESOURCE_EXHAUSTED forever; fail fast instead. */
function guardWrite(promise) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error(
      'Firestore is not accepting writes (free Spark daily write quota used up). ' +
      'It resets around 3:00 PM PH time — re-run this script then.',
    )), WRITE_TIMEOUT_MS)),
  ]);
}

/** Mirrors spotQrData() in lib/utils/spot_qr_helper.dart (no lat/lng). */
function boothQrPayload(municipalityId, spotId) {
  const url = new URL(CHECK_IN_BASE_URL);
  url.searchParams.set('type', 'spot');
  url.searchParams.set('municipality_id', municipalityId);
  url.searchParams.set('spot_id', spotId);
  return url.toString();
}

async function main() {
  const admin = initAdmin();
  const db = admin.firestore();
  const spots = db.collection('tourist_spots');
  console.log(apply ? 'APPLY mode\n' : 'DRY RUN — nothing is written\n');

  if (remove) {
    const tagged = await spots.where('eventTag', '==', EVENT_TAG).get();
    tagged.docs.forEach((d) => console.log(`remove tourist_spots/${d.id}  ${d.data().name}`));
    if (apply) {
      for (const d of tagged.docs) await guardWrite(d.ref.delete());
      console.log(`\nDeleted ${tagged.size} booth(s). Their qr_checkins history is kept.`);
    } else {
      console.log(`\n${tagged.size} booth(s) would be deleted. Re-run with --apply.`);
    }
    return;
  }

  const anchorSnap = await spots.where('name', '==', ANCHOR_SPOT_NAME).limit(1).get();
  if (anchorSnap.empty) {
    throw new Error(`Anchor spot "${ANCHOR_SPOT_NAME}" not found in tourist_spots.`);
  }
  const anchor = anchorSnap.docs[0].data();
  const municipalityId = String(anchor.municipalityId || '').trim().toLowerCase();
  const municipality = String(anchor.municipality || '').trim() || 'Oroquieta City';
  if (!municipalityId) throw new Error('Anchor spot has no municipalityId.');
  console.log(`Municipality: ${municipality} (${municipalityId})\n`);

  for (const booth of BOOTHS) {
    const ref = spots.doc(booth.id);
    const existing = await ref.get();
    const qrPayload = boothQrPayload(municipalityId, booth.id);
    console.log(`${existing.exists ? 'update' : 'create'}  ${booth.name}`);
    console.log(`        ${qrPayload}`);
    if (!apply) continue;
    await guardWrite(ref.set({
      name: booth.name,
      category: CATEGORY,
      municipality,
      municipalityId,
      description: `Event booth QR for the ${EVENT_TAG} visit test.`,
      status: 'Active',
      rating: 0,
      visitors: existing.exists ? existing.data().visitors || 0 : 0,
      qrValue: booth.id,
      qr_payload: qrPayload,
      eventTag: EVENT_TAG,
      latitude: admin.firestore.FieldValue.delete(),
      longitude: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(existing.exists ? {} : {createdAt: admin.firestore.FieldValue.serverTimestamp()}),
    }, {merge: true}));
  }

  if (!apply) {
    console.log('\nRe-run with --apply to write.');
    return;
  }

  console.log('\nRead back:');
  for (const booth of BOOTHS) {
    const d = (await spots.doc(booth.id).get()).data() || {};
    const hasCoords = d.latitude !== undefined || d.longitude !== undefined;
    console.log(
      `  ${booth.id.padEnd(28)} ${String(d.name).padEnd(34)} ` +
      `${d.status}  coords=${hasCoords ? 'YES (unexpected)' : 'none'}  tag=${d.eventTag}`,
    );
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
