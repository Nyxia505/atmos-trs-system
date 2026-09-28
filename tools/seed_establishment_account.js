// Creates (or repairs) a ready-to-use tourism establishment login so the app
// routes straight to /establishment-dashboard (verified + active, no OTP).
//
// Usage:
//   node tools/seed_establishment_account.js <email> <password> ["Business Name"] ["Municipality"] ["Category"] ["Barangay"]
// Example:
//   node tools/seed_establishment_account.js "melane'shotel@gmail.com" melane123 "Melane's Hotel" "Oroquieta City" Hotel "Poblacion I"

const {initializeApp} = require('firebase/app');
const {
  getAuth,
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
} = require('firebase/auth');
const {
  getFirestore,
  doc,
  setDoc,
  serverTimestamp,
} = require('firebase/firestore/lite');

const LODGING = new Set(['hotel', 'resort', 'glamping', 'camping', 'inn',
  'pension house', 'homestay', 'lodge', 'hostel', 'apartelle']);

function municipalityIdFromName(name) {
  const n = name.trim().toLowerCase();
  if (n === 'ozamiz city' || n === 'ozamis city') return 'ozamiz';
  return n.replace(/\s+city$/, '').replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '');
}

async function signInOrCreate(auth, email, password) {
  try {
    return await signInWithEmailAndPassword(auth, email, password);
  } catch (e) {
    const code = e && e.code ? e.code : '';
    if (code === 'auth/user-not-found' ||
        code === 'auth/invalid-credential' ||
        code === 'auth/invalid-login-credentials') {
      try {
        console.log('Auth user not found — creating it...');
        return await createUserWithEmailAndPassword(auth, email, password);
      } catch (createErr) {
        if (createErr && createErr.code === 'auth/email-already-in-use') {
          throw new Error(
              'Email exists in Firebase Auth but the password does not match. ' +
              'Reset it in Firebase Console → Authentication, then rerun.');
        }
        throw createErr;
      }
    }
    throw e;
  }
}

async function main() {
  const [emailArg, password, businessArg, municipalityArg, categoryArg,
    barangayArg] = process.argv.slice(2);
  if (!emailArg || !password) {
    console.error('Usage: node tools/seed_establishment_account.js <email> ' +
        '<password> ["Business Name"] ["Municipality"] ["Category"] ["Barangay"]');
    process.exit(1);
  }
  const email = emailArg.trim().toLowerCase();
  const businessName = (businessArg || 'Demo Establishment').trim();
  const municipality = (municipalityArg || 'Oroquieta City').trim();
  const category = (categoryArg || 'Hotel').trim();
  const barangay = (barangayArg || 'Poblacion I').trim();
  const municipalityId = municipalityIdFromName(municipality);
  const lodging = LODGING.has(category.toLowerCase());

  const app = initializeApp({
    apiKey: 'AIzaSyAQcksY7LOLTeGKx_OwhDQ2wNLJ4o_OgtU',
    authDomain: 'atmos-trs-system.firebaseapp.com',
    projectId: 'atmos-trs-system',
    appId: '1:760231001760:web:609c5e6783594773cf13c5',
  });
  const auth = getAuth(app);
  const db = getFirestore(app);

  console.log(`Signing in as ${email}...`);
  const cred = await signInOrCreate(auth, email, password);
  const uid = cred.user.uid;
  console.log(`uid=${uid}`);

  const username = email.split('@')[0].replace(/[^a-z0-9._-]/g, '');
  const common = {
    email,
    businessName,
    municipality,
    municipalityId,
    barangay,
    category,
    username,
    status: 'active',
    updatedAt: serverTimestamp(),
    ...(lodging ? {checkInTime: '14:00', checkOutTime: '12:00'} : {}),
  };

  await setDoc(doc(db, 'users', uid), {
    ...common,
    firebaseUid: uid,
    fullName: businessName,
    role: 'tourism_establishment',
    isVerified: true,
    createdAt: serverTimestamp(),
  }, {merge: true});

  await setDoc(doc(db, 'accommodation_establishments', uid), {
    ...common,
    id: uid,
    name: businessName,
    type: category,
    ownerName: businessName,
    location: `${barangay}, ${municipality}, Misamis Occidental`,
    ownerUid: uid,
    authUid: uid,
    createdAt: serverTimestamp(),
  }, {merge: true});

  console.log('\nDone. Establishment account is verified + active.');
  console.log(`Email:    ${email}`);
  console.log(`Password: ${password}`);
  console.log('Log in from the app → goes to /establishment-dashboard.');
  process.exit(0);
}

main().catch((e) => {
  console.error('Seeding failed:', e && e.message ? e.message : e);
  process.exit(1);
});
