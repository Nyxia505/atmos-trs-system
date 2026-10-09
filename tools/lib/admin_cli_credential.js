/**
 * Shared firebase-admin bootstrap for tools/ scripts.
 *
 * Credentials: GOOGLE_APPLICATION_CREDENTIALS service-account key if set,
 * otherwise the local `firebase login` session. firebase-admin is loaded from
 * functions/node_modules when it is not installed at the repo root.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const {execSync} = require('child_process');

const PROJECT_ID = 'atmos-trs-system';

function loadAdmin() {
  try {
    return require('firebase-admin');
  } catch (_) {
    return require(path.join(__dirname, '..', '..', 'functions', 'node_modules', 'firebase-admin'));
  }
}

const admin = loadAdmin();

/** Falls back to the local `firebase login` session when no key is set. */
function firebaseCliCredential() {
  const store = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  if (!fs.existsSync(store)) return null;
  const refreshToken = JSON.parse(fs.readFileSync(store, 'utf8'))?.tokens?.refresh_token;
  if (!refreshToken) return null;
  const globalRoot = execSync('npm root -g', {encoding: 'utf8'}).trim();
  const api = require(path.join(globalRoot, 'firebase-tools', 'lib', 'api.js'));
  // Firestore only accepts a cert or ADC, so expose the CLI session as a
  // short-lived ADC file in the OS temp dir (never inside the repo).
  const adcFile = path.join(os.tmpdir(), `atmos-admin-adc-${process.pid}.json`);
  fs.writeFileSync(adcFile, JSON.stringify({
    type: 'authorized_user',
    client_id: api.clientId(),
    client_secret: api.clientSecret(),
    refresh_token: refreshToken,
    quota_project_id: PROJECT_ID,
  }));
  process.on('exit', () => {
    try {
      fs.unlinkSync(adcFile);
    } catch (_) {}
  });
  process.env.GOOGLE_APPLICATION_CREDENTIALS = adcFile;
  process.env.GOOGLE_CLOUD_QUOTA_PROJECT = PROJECT_ID;
  return admin.credential.applicationDefault();
}

/** Initializes the default firebase-admin app (exits when no credentials). */
function initAdmin() {
  if (admin.apps.length) return admin;
  let credential;
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    credential = admin.credential.applicationDefault();
  } else {
    try {
      credential = firebaseCliCredential();
    } catch (err) {
      console.warn(`Firebase CLI login not usable: ${err.message}`);
    }
    if (!credential) {
      console.error(
        'No credentials. Either run `firebase login`, or\n' +
        'Firebase Console > Project settings > Service accounts > Generate new private key,\n' +
        'save it OUTSIDE the repo, then:\n' +
        '  $env:GOOGLE_APPLICATION_CREDENTIALS="C:\\keys\\atmos-admin.json"',
      );
      process.exit(1);
    }
    console.log('Using Firebase CLI login credentials.');
  }
  admin.initializeApp({credential, projectId: PROJECT_ID});
  return admin;
}

module.exports = {admin, initAdmin, PROJECT_ID};
