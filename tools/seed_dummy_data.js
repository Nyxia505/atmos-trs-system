const {initializeApp} = require('firebase/app');
const {getAuth, signInWithEmailAndPassword} = require('firebase/auth');
const {getFunctions, httpsCallable} = require('firebase/functions');

const DEMO_GOVERNOR_EMAIL = 'governor.atmos@misocc-demo.ph';
const DEMO_GOVERNOR_PASSWORD = 'Asenso@MISocc#2026!Gov';

async function main() {
  const municipalityId = (process.argv[2] || 'jimenez').trim().toLowerCase();
  const reportFocus = (process.argv[3] || 'monthly').trim().toLowerCase();

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
  const callSeed = httpsCallable(functions, 'seedTourismDummyData');
  console.log(
    `Seeding dummy report data for ${municipalityId} (focus: ${reportFocus})`,
  );
  const response = await callSeed({municipalityId, reportFocus});
  const data = response.data;
  console.log('seedTourismDummyData response:', JSON.stringify(data, null, 2));

  if (data && data.testLogins) {
    console.log('\n--- Monthly report login ---');
    console.log(`Email:    ${data.testLogins.monthlyReportsEmail}`);
    console.log(`Password: ${data.testLogins.monthlyReportsPassword}`);
    console.log('\n--- Then in app: Reports → Monthly Report → Export ---');
  }
}

main().catch((e) => {
  console.error('Seeding failed:', e);
  process.exit(1);
});
