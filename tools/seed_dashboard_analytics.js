const {initializeApp} = require('firebase/app');
const {getAuth, signInWithEmailAndPassword} = require('firebase/auth');
const {getFunctions, httpsCallable} = require('firebase/functions');

const DEMO_GOVERNOR_EMAIL = 'governor.atmos@misocc-demo.ph';
const DEMO_GOVERNOR_PASSWORD = 'Asenso@MISocc#2026!Gov';

async function main() {
  const municipalityId = (process.argv[2] || 'oroquieta').trim().toLowerCase();
  const localCount = Number(process.argv[3] || 14);
  const foreignCount = Number(process.argv[4] || 6);
  const seedAll = process.argv.includes('--all');

  const app = initializeApp({
    apiKey: 'AIzaSyAQcksY7LOLTeGKx_OwhDQ2wNLJ4o_OgtU',
    authDomain: 'atmos-trs-system.firebaseapp.com',
    projectId: 'atmos-trs-system',
    appId: '1:760231001760:web:609c5e6783594773cf13c5',
  });

  const auth = getAuth(app);
  console.log(`Signing in as ${DEMO_GOVERNOR_EMAIL}...`);
  await signInWithEmailAndPassword(
    auth,
    DEMO_GOVERNOR_EMAIL,
    DEMO_GOVERNOR_PASSWORD,
  );

  const functions = getFunctions(app, 'asia-southeast1');
  const callSeed = httpsCallable(functions, 'seedLguAnalyticsData');
  console.log(
    seedAll
      ? `Seeding ALL municipalities (${localCount} Filipino + ${foreignCount} foreign each)`
      : `Seeding ${municipalityId} (${localCount} Filipino + ${foreignCount} foreign)`,
  );
  const response = await callSeed({
    municipalityId,
    seedAllMunicipalities: seedAll,
    localCount,
    foreignCount,
    checkInsPerTourist: 2,
  });
  console.log('seedLguAnalyticsData:', JSON.stringify(response.data, null, 2));
}

main().catch((e) => {
  console.error('Seeding failed:', e);
  process.exit(1);
});
