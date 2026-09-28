// Removes demo stays / reviews created by tools/seed_establishment_stays.js
// (only docs tagged seed == 'demo'). Real guest data is never touched.
//
// Usage:
//   node tools/cleanup_establishment_stays.js <hotelEmail> <hotelPassword> [touristEmail] [touristPassword]
// Example:
//   node tools/cleanup_establishment_stays.js "melane'shotel@gmail.com" melane123

const {initializeApp} = require('firebase/app');
const {getAuth, signInWithEmailAndPassword} = require('firebase/auth');
const {
  getFirestore,
  collection,
  query,
  where,
  getDocs,
  getDoc,
  doc,
  deleteDoc,
  setDoc,
  deleteField,
} = require('firebase/firestore/lite');

const FIREBASE_CONFIG = {
  apiKey: 'AIzaSyAQcksY7LOLTeGKx_OwhDQ2wNLJ4o_OgtU',
  authDomain: 'atmos-trs-system.firebaseapp.com',
  projectId: 'atmos-trs-system',
  appId: '1:760231001760:web:609c5e6783594773cf13c5',
};

const STAYS = 'establishment_stay_requests';
const REVIEWS = 'establishment_stay_reviews';
const ESTABLISHMENTS = 'accommodation_establishments';
const DEFAULT_TOURIST_EMAIL = 'demo.tourist.seed@atmos-trs.test';
const DEFAULT_TOURIST_PASSWORD = 'DemoSeed#2026';

/** Signed in as the hotel: deletes its seed == 'demo' stay requests. */
async function deleteSeededStays(db, hotelUid) {
  const snap = await getDocs(
      query(collection(db, STAYS), where('establishmentId', '==', hotelUid)));
  let n = 0;
  for (const d of snap.docs) {
    if (d.data().seed !== 'demo') continue;
    await deleteDoc(d.ref);
    n++;
  }
  return n;
}

/** Signed in as the demo tourist: deletes its seeded reviews for this hotel. */
async function deleteSeededReviews(db, hotelUid, touristUid) {
  const snap = await getDocs(
      query(collection(db, REVIEWS), where('establishmentId', '==', hotelUid)));
  let n = 0;
  for (const d of snap.docs) {
    const data = d.data();
    if (data.seed !== 'demo' || data.touristId !== touristUid) continue;
    await deleteDoc(d.ref);
    n++;
  }
  return n;
}

/** Signed in as the hotel: reverts room setup only if the seed created it. */
async function revertSeededRooms(db, hotelUid) {
  const ref = doc(db, ESTABLISHMENTS, hotelUid);
  const snap = await getDoc(ref);
  if (!snap.exists() || snap.data().seedDemoRooms !== true) return false;
  await setDoc(ref, {
    roomCount: deleteField(),
    roomInventory: deleteField(),
    disabledRooms: deleteField(),
    seedDemoRooms: deleteField(),
  }, {merge: true});
  return true;
}

async function main() {
  const [hotelEmailArg, hotelPassword, touristEmailArg, touristPasswordArg] =
      process.argv.slice(2);
  if (!hotelEmailArg || !hotelPassword) {
    console.error('Usage: node tools/cleanup_establishment_stays.js ' +
        '<hotelEmail> <hotelPassword> [touristEmail] [touristPassword]');
    process.exit(1);
  }
  const touristEmail =
      (touristEmailArg || DEFAULT_TOURIST_EMAIL).trim().toLowerCase();
  const touristPassword = touristPasswordArg || DEFAULT_TOURIST_PASSWORD;

  const app = initializeApp(FIREBASE_CONFIG);
  const auth = getAuth(app);
  const db = getFirestore(app);

  const hotel = await signInWithEmailAndPassword(
      auth, hotelEmailArg.trim().toLowerCase(), hotelPassword);
  const hotelUid = hotel.user.uid;
  console.log(`Hotel uid=${hotelUid}`);

  const stays = await deleteSeededStays(db, hotelUid);
  console.log(`Deleted ${stays} demo stay request(s).`);
  const rooms = await revertSeededRooms(db, hotelUid);
  if (rooms) console.log('Reverted seeded room setup (roomCount/inventory).');

  try {
    const tourist = await signInWithEmailAndPassword(
        auth, touristEmail, touristPassword);
    const reviews = await deleteSeededReviews(db, hotelUid, tourist.user.uid);
    console.log(`Deleted ${reviews} demo review(s).`);
  } catch (e) {
    console.log(`Skipped reviews (demo tourist sign-in failed: ${e.code || e.message}).`);
  }
  process.exit(0);
}

module.exports = {
  FIREBASE_CONFIG,
  STAYS,
  REVIEWS,
  ESTABLISHMENTS,
  DEFAULT_TOURIST_EMAIL,
  DEFAULT_TOURIST_PASSWORD,
  deleteSeededStays,
  deleteSeededReviews,
};

if (require.main === module) {
  main().catch((e) => {
    console.error('Cleanup failed:', e && e.message ? e.message : e);
    process.exit(1);
  });
}
