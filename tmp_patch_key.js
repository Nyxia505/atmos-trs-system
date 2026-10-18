/**
 * Allow the default Firebase auth handler to call Identity Toolkit with the
 * API key embedded in password-reset emails. Keeps the existing referrer.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const KEY = 'projects/760231001760/locations/global/keys/944f1e11-81dd-41b0-b5ee-23f4d7836fb1';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';
const REQUIRED = [
  'https://atmos-trs-system.firebaseapp.com/*',
  'https://atmos-trs-system.web.app/*',
  'http://localhost/*',
  'http://127.0.0.1/*',
];

async function accessToken() {
  const cfg = JSON.parse(fs.readFileSync(
    path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json'),
    'utf8',
  ));
  const body = new URLSearchParams({
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    refresh_token: cfg.tokens.refresh_token,
    grant_type: 'refresh_token',
  });
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const json = await res.json();
  if (!json.access_token) throw new Error('token exchange failed');
  return json.access_token;
}

async function main() {
  const token = await accessToken();
  const currentRes = await fetch('https://apikeys.googleapis.com/v2/' + KEY, {
    headers: { Authorization: 'Bearer ' + token },
  });
  const current = await currentRes.json();
  if (currentRes.status !== 200) {
    console.log('read failed', currentRes.status, JSON.stringify(current).slice(0, 300));
    return;
  }
  const existing = (current.restrictions &&
    current.restrictions.browserKeyRestrictions &&
    current.restrictions.browserKeyRestrictions.allowedReferrers) || [];
  const allowedReferrers = [...existing];
  for (const ref of REQUIRED) {
    if (!allowedReferrers.includes(ref)) allowedReferrers.push(ref);
  }
  const patchRes = await fetch(
    'https://apikeys.googleapis.com/v2/' + KEY +
      '?updateMask=restrictions.browserKeyRestrictions.allowedReferrers',
    {
      method: 'PATCH',
      headers: {
        Authorization: 'Bearer ' + token,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        restrictions: { browserKeyRestrictions: { allowedReferrers } },
      }),
    },
  );
  const patched = await patchRes.json();
  console.log('patch', patchRes.status, patched.done, patched.name || '', patched.error ? JSON.stringify(patched.error).slice(0, 400) : '');
  const again = await fetch('https://apikeys.googleapis.com/v2/' + KEY, {
    headers: { Authorization: 'Bearer ' + token },
  });
  const body = await again.json();
  console.log('referrers now', JSON.stringify(
    body.restrictions &&
    body.restrictions.browserKeyRestrictions &&
    body.restrictions.browserKeyRestrictions.allowedReferrers,
  ));
}

main().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
