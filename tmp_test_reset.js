/**
 * End-to-end password reset against the default handler key:
 * check twice, HTTP GET the handler, confirm, sign in, delete.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT = 'atmos-trs-system';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';
const REFERER = 'https://atmos-trs-system.firebaseapp.com/__/auth/action';
const NEW_PASSWORD = 'ResetOk1!Aa';

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

async function adminPost(token, urlPath, payload) {
  const res = await fetch('https://identitytoolkit.googleapis.com/v1/' + urlPath, {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + token,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  return { status: res.status, json: await res.json() };
}

async function resetCall(apiKey, payload) {
  const res = await fetch(
    'https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?key=' + apiKey,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Referer: REFERER,
      },
      body: JSON.stringify(payload),
    },
  );
  const json = await res.json();
  return {
    status: res.status,
    error: json.error && json.error.message,
    hasEmail: Boolean(json.email),
  };
}

async function main() {
  const token = await accessToken();
  for (const configUrl of [
    `https://identitytoolkit.googleapis.com/admin/v2/projects/${PROJECT}/config`,
    `https://identitytoolkit.googleapis.com/v2/projects/${PROJECT}/config`,
  ]) {
    const res = await fetch(configUrl, { headers: { Authorization: 'Bearer ' + token } });
    const text = await res.text();
    let json;
    try { json = JSON.parse(text); } catch { json = null; }
    const domains = json && (json.authorizedDomains || (json.signIn && json.signIn.authorizedDomains));
    console.log('config', res.status, configUrl.split('/').slice(-2).join('/'), domains || text.slice(0, 180));
    if (domains) break;
  }

  const email = `atmos-pwreset-probe-${Date.now()}@misocc-seed.ph`;
  const created = await adminPost(token, `projects/${PROJECT}/accounts`, {
    email,
    password: 'OldPass1!Aa',
  });
  if (created.status !== 200) {
    console.log('create failed', created.status, JSON.stringify(created.json).slice(0, 250));
    return;
  }
  const localId = created.json.localId;
  try {
    const link = await adminPost(token, `projects/${PROJECT}/accounts:sendOobCode`, {
      requestType: 'PASSWORD_RESET',
      email,
      returnOobLink: true,
    });
    const url = new URL(link.json.oobLink);
    const apiKey = url.searchParams.get('apiKey');
    const code = url.searchParams.get('oobCode');
    console.log('link host', url.host + url.pathname, 'continue', url.searchParams.has('continueUrl'));

    const first = await resetCall(apiKey, { oobCode: code });
    const second = await resetCall(apiKey, { oobCode: code });
    console.log('check 1', first.status, first.error || (first.hasEmail ? 'valid' : 'ok'));
    console.log('check 2', second.status, second.error || (second.hasEmail ? 'still-valid' : 'ok'));

    const page = await fetch(url.toString(), { headers: { Referer: REFERER } });
    console.log('handler GET', page.status, page.headers.get('content-type'));
    const afterGet = await resetCall(apiKey, { oobCode: code });
    console.log('check after GET', afterGet.status, afterGet.error || (afterGet.hasEmail ? 'still-valid' : 'ok'));

    const confirmed = await resetCall(apiKey, { oobCode: code, newPassword: NEW_PASSWORD });
    console.log('confirm', confirmed.status, confirmed.error || 'password-updated');
    const reused = await resetCall(apiKey, { oobCode: code });
    console.log('check after confirm', reused.status, reused.error || 'unexpected-valid');

    const signIn = await fetch(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=' + apiKey,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Referer: REFERER },
        body: JSON.stringify({ email, password: NEW_PASSWORD, returnSecureToken: true }),
      },
    );
    const signed = await signIn.json();
    console.log('sign in', signIn.status, signed.error ? signed.error.message : 'session-created');
  } finally {
    const del = await adminPost(token, `projects/${PROJECT}/accounts:delete`, { localId });
    console.log('deleted temp user', del.status === 200);
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
