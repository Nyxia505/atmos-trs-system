/**
 * Disposable probe: does checkActionCode consume a password-reset oobCode,
 * and does a second generatePasswordResetLink invalidate the first?
 * Creates and deletes one temporary Auth user. Does not print codes or tokens.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const PROJECT = 'atmos-trs-system';
const CLIENT_ID = '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com';
const CLIENT_SECRET = 'j9iVZfS8kkCEFUPaAeJV0sAi';

async function accessToken() {
  const cfgPath = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  const refresh = cfg.tokens && cfg.tokens.refresh_token;
  if (!refresh) throw new Error('No Firebase CLI refresh token');
  const body = new URLSearchParams({
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    refresh_token: refresh,
    grant_type: 'refresh_token',
  });
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const json = await res.json();
  if (!json.access_token) throw new Error('token exchange failed ' + res.status);
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
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = { raw: text.slice(0, 200) }; }
  return { status: res.status, json };
}

function oobFromLink(link) {
  const url = new URL(link);
  return {
    host: url.host,
    path: url.pathname,
    params: [...url.searchParams.keys()],
    hasContinue: url.searchParams.has('continueUrl'),
    code: url.searchParams.get('oobCode'),
  };
}

async function checkCode(apiKey, code, referer) {
  const headers = { 'Content-Type': 'application/json' };
  if (referer) headers.Referer = referer;
  const res = await fetch(
    'https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?key=' + apiKey,
    {
      method: 'POST',
      headers,
      body: JSON.stringify({ oobCode: code }),
    },
  );
  const json = await res.json();
  return { status: res.status, error: json.error && json.error.message, hasEmail: Boolean(json.email) };
}

async function describeKeys(token, linkApiKey) {
  const res = await fetch(
    'https://apikeys.googleapis.com/v2/projects/760231001760/locations/global/keys',
    { headers: { Authorization: 'Bearer ' + token } },
  );
  const json = await res.json();
  if (!json.keys) {
    console.log('list keys failed', res.status, JSON.stringify(json).slice(0, 300));
    return;
  }
  const web = 'AIzaSyAQcksY7LOLTeGKx_OwhDQ2wNLJ4o_OgtU';
  const android = 'AIzaSyBuYILpEr9o7m3KUblvE90KrPouvK4mHm0';
  console.log('oob link key is web options key', linkApiKey === web);
  console.log('oob link key is android options key', linkApiKey === android);
  for (const key of json.keys) {
    const detailRes = await fetch(
      'https://apikeys.googleapis.com/v2/' + key.name + '?$fields=displayName,keyString,restrictions',
      { headers: { Authorization: 'Bearer ' + token } },
    );
    const detail = await detailRes.json();
    const value = detail.keyString || '';
    console.log(
      'seen',
      detail.displayName || key.displayName,
      'http',
      detailRes.status,
      'keyLen',
      value.length,
      'fields',
      Object.keys(detail).join(','),
    );
    if (!value || (value !== linkApiKey && value !== web && value !== android)) continue;
    const which = [
      value === linkApiKey ? 'OOB_LINK_KEY' : '',
      value === web ? 'WEB_OPTIONS' : '',
      value === android ? 'ANDROID_OPTIONS' : '',
    ].filter(Boolean).join('+');
    const restrictions = detail.restrictions || {};
    console.log('key', which, 'name', detail.displayName);
    console.log('browser restrictions', JSON.stringify(restrictions.browserKeyRestrictions || null));
    console.log('android restrictions', JSON.stringify(restrictions.androidKeyRestrictions || null));
    console.log('ios restrictions', JSON.stringify(restrictions.iosKeyRestrictions || null));
    const targets = (restrictions.apiTargets || []).map((t) => t.service);
    console.log('identitytoolkit allowed', targets.length === 0 || targets.includes('identitytoolkit.googleapis.com'));
  }
}

async function main() {
  const token = await accessToken();
  const email = `atmos-pwreset-probe-${Date.now()}@misocc-seed.ph`;
  const created = await adminPost(token, `projects/${PROJECT}/accounts`, {
    email,
    password: 'ProbeTest1!Aa',
    emailVerified: false,
  });
  if (created.status !== 200) {
    console.log('create failed', created.status, JSON.stringify(created.json).slice(0, 300));
    return;
  }
  const localId = created.json.localId;
  try {
    const link1 = await adminPost(token, `projects/${PROJECT}/accounts:sendOobCode`, {
      requestType: 'PASSWORD_RESET',
      email,
      returnOobLink: true,
    });
    if (link1.status !== 200) {
      console.log('link1 failed', link1.status, JSON.stringify(link1.json).slice(0, 400));
      return;
    }
    const info1 = oobFromLink(link1.json.oobLink);
    const apiKey = new URL(link1.json.oobLink).searchParams.get('apiKey');
    await describeKeys(token, apiKey);
    const referers = [
      '',
      'https://atmos-trs-system.firebaseapp.com/',
      'https://atmos-trs-system.firebaseapp.com/__/auth/action',
      'https://atmos-trs-system.web.app/',
      'https://atmos-trs-system.web.app/forgot-password',
      'http://localhost/',
      'http://localhost:5000/',
    ];
    console.log('handler', info1.host + info1.path);
    console.log('link params', info1.params.join(','));
    for (const ref of referers) {
      const result = await checkCode(apiKey, info1.code, ref || null);
      console.log(
        'referer',
        ref || '<empty>',
        result.status,
        result.error || (result.hasEmail ? 'email-returned' : 'ok'),
      );
    }

    const link2 = await adminPost(token, `projects/${PROJECT}/accounts:sendOobCode`, {
      requestType: 'PASSWORD_RESET',
      email,
      returnOobLink: true,
      continueUrl: 'https://atmos-trs-system.web.app/forgot-password',
      canHandleCodeInApp: true,
    });
    console.log('link2 status', link2.status, link2.json.oobLink ? 'has-link' : JSON.stringify(link2.json).slice(0, 250));
    if (link2.json && link2.json.oobLink) {
      const info2 = oobFromLink(link2.json.oobLink);
      console.log('link2 params', info2.params.join(','));
      console.log('link2 continue', info2.hasContinue);
      const oldAfterNew = await checkCode(apiKey, info1.code);
      const neu = await checkCode(apiKey, info2.code);
      console.log('code1 after second generate', oldAfterNew.status, oldAfterNew.error || 'still-valid');
      console.log('code2 check', neu.status, neu.error || (neu.hasEmail ? 'email-returned' : 'ok'));
    }
  } finally {
    const del = await adminPost(token, `projects/${PROJECT}/accounts:delete`, { localId });
    console.log('deleted temp user', del.status === 200);
  }
}

main().catch((e) => {
  console.error('probe failed', e.message);
  process.exitCode = 1;
});
