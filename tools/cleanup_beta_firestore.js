/**
 * Removes dummy seed data from Firestore before ATMOS-TRS beta.
 *
 * Usage (dev/staging only):
 *   set GOOGLE_APPLICATION_CREDENTIALS=path\to\serviceAccount.json
 *   node tools/cleanup_beta_firestore.js
 *
 * Dry run (default): logs counts only.
 *   node tools/cleanup_beta_firestore.js --apply
 */

const admin = require('firebase-admin');

const apply = process.argv.includes('--apply');

function isDummyTourist(data, id) {
  const uid = (data.firebaseUid || data.uid || id || '').toString();
  const email = (data.email || '').toString().toLowerCase();
  return (
    uid.startsWith('dummy_tourist_') ||
    uid.startsWith('demo_analytics_') ||
    email.includes('@dummy-tourist.test') ||
    email.includes('@misocc-demo-analytics.ph') ||
    data.source === 'dummy_seed' ||
    data.seedTag === 'dashboard_analytics_v1' ||
    data.demoAnalytics === true
  );
}

function isDummyCheckIn(data) {
  const uid = (data.userId || data.tourist_id || data.user_id || '').toString();
  const email = (data.touristEmail || data.email || '').toString().toLowerCase();
  return (
    data.source === 'dummy_seed' ||
    data.seedTag === 'dashboard_analytics_v1' ||
    data.demoAnalytics === true ||
    uid.startsWith('dummy_tourist_') ||
    uid.startsWith('demo_analytics_') ||
    email.includes('@dummy-tourist.test') ||
    email.includes('@misocc-demo-analytics.ph')
  );
}

async function deleteQueryBatch(query, label) {
  const snap = await query.get();
  console.log(`${label}: ${snap.size} document(s) matched`);
  if (!apply || snap.empty) return;
  const batch = admin.firestore().batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  console.log(`  deleted ${snap.size} ${label}`);
}

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  const db = admin.firestore();

  console.log(apply ? 'APPLY mode — deleting documents' : 'DRY RUN — no deletes');

  const touristsSnap = await db.collection('tourists').get();
  let touristDeletes = 0;
  for (const doc of touristsSnap.docs) {
    if (isDummyTourist(doc.data(), doc.id)) touristDeletes++;
  }
  console.log(`tourists (dummy): ${touristDeletes}`);

  const checkInsSnap = await db.collection('qr_checkins').get();
  let checkInDeletes = 0;
  for (const doc of checkInsSnap.docs) {
    if (isDummyCheckIn(doc.data())) checkInDeletes++;
  }
  console.log(`qr_checkins (dummy): ${checkInDeletes}`);

  if (!apply) {
    console.log('\nRe-run with --apply to delete.');
    return;
  }

  for (const doc of touristsSnap.docs) {
    if (!isDummyTourist(doc.data(), doc.id)) continue;
    await doc.ref.delete();
  }
  for (const doc of checkInsSnap.docs) {
    if (!isDummyCheckIn(doc.data())) continue;
    await doc.ref.delete();
  }

  console.log('Cleanup complete.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
