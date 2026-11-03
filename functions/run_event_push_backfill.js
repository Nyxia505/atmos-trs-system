/**
 * One-shot sender for installed tourist APKs.
 * Uses the Firebase CLI login (cloud-platform) already on this machine.
 * Does not print tokens. Skips expired, draft, rejected, and already-sent events.
 *
 *   node functions/run_event_push_backfill.js            # list only
 *   node functions/run_event_push_backfill.js --send     # deliver unsent events
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const {announcementPushCopy, isTourismEvent} = require('./event_push_copy');

const PROJECT = 'atmos-trs-system';
const TOPIC = 'governor_announcements';
const CHANNEL = 'atmos_announcement_heads_up';
const BATCH = 20;
const dryRun = !process.argv.includes('--send');

function loadAccessToken() {
  const file = path.join(
    os.homedir(),
    '.config',
    'configstore',
    'firebase-tools.json',
  );
  const stored = JSON.parse(fs.readFileSync(file, 'utf8'));
  const token = stored.tokens && stored.tokens.access_token;
  if (!token) throw new Error('Firebase CLI access token is missing. Run firebase login.');
  return token;
}

function str(fields, key) {
  const value = fields && fields[key];
  if (!value || Object.prototype.hasOwnProperty.call(value, 'nullValue')) return '';
  return String(value.stringValue || '').trim();
}

function bool(fields, key) {
  return !!(fields && fields[key] && fields[key].booleanValue === true);
}

function time(fields, key) {
  const raw = fields && fields[key] && fields[key].timestampValue;
  if (!raw) return null;
  const date = new Date(raw);
  return Number.isFinite(date.getTime()) ? date : null;
}

function intOf(fields, key) {
  const raw = fields && fields[key];
  if (!raw || raw.integerValue == null) return null;
  const n = Number(raw.integerValue);
  return Number.isFinite(n) ? n : null;
}

function strings(fields, key) {
  const values = fields && fields[key] && fields[key].arrayValue
    ? fields[key].arrayValue.values || []
    : [];
  return values.map((item) => String(item.stringValue || '').trim()).filter(Boolean);
}

function claimed(fields) {
  const value = fields && fields.fcmSent_published;
  return !!(value && !Object.prototype.hasOwnProperty.call(value, 'nullValue'));
}

function toData(fields) {
  return {
    title: str(fields, 'title'),
    content: str(fields, 'content') || str(fields, 'message'),
    type: str(fields, 'type'),
    status: str(fields, 'status'),
    published: bool(fields, 'published'),
    scheduleState: str(fields, 'scheduleState'),
    location: str(fields, 'location'),
    municipalityName: str(fields, 'municipalityName'),
    allDay: bool(fields, 'allDay'),
    date: str(fields, 'date'),
    durationDays: intOf(fields, 'durationDays'),
    startsAt: time(fields, 'startsAt'),
    endsAt: time(fields, 'endsAt'),
    imageUrl: str(fields, 'imageUrl'),
    imageUrls: strings(fields, 'imageUrls'),
  };
}

async function api(token, url, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(`${res.status} ${JSON.stringify(json).slice(0, 400)}`);
    err.status = res.status;
    throw err;
  }
  return json;
}

async function listAnnouncements(token) {
  const docs = [];
  let pageToken = '';
  while (docs.length < 300) {
    const url = new URL(
      `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/announcements`,
    );
    url.searchParams.set('pageSize', '100');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const json = await api(token, url);
    docs.push(...(json.documents || []));
    pageToken = json.nextPageToken || '';
    if (!pageToken) break;
  }
  return docs;
}

async function writeClaim(token, id, clear) {
  const name =
    `projects/${PROJECT}/databases/(default)/documents/announcements/${id}`;
  const now = new Date().toISOString();
  const fields = clear
    ? {}
    : {
      fcmSent_published: {timestampValue: now},
      fcmSentAt: {timestampValue: now},
    };
  await api(
    token,
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:commit`,
    {
      method: 'POST',
      body: JSON.stringify({
        writes: [
          {
            update: {name, fields},
            updateMask: {fieldPaths: ['fcmSent_published', 'fcmSentAt']},
            currentDocument: {exists: true},
          },
        ],
      }),
    },
  );
}

async function sendTopic(token, id, copy, includeImage) {
  const data = {
    type: copy.type || 'Event',
    announcementId: id,
    eventType: copy.type || 'Event',
    title: copy.title,
    body: copy.body,
    notificationType: copy.notificationType || 'tourism_event',
    eventId: id,
    location: copy.location || '',
    eventDate: copy.eventDate || '',
  };
  const image = includeImage ? copy.imageUrl : '';
  if (image) data.imageUrl = image;
  const notification = {title: copy.title, body: copy.body};
  if (image) notification.image = image;
  const androidNotification = {
    channelId: CHANNEL,
    sound: 'default',
    tag: id,
  };
  if (image) androidNotification.image = image;
  await api(
    token,
    `https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`,
    {
      method: 'POST',
      body: JSON.stringify({
        message: {
          topic: TOPIC,
          notification,
          data,
          android: {
            priority: 'HIGH',
            ttl: '604800s',
            collapseKey: id,
            notification: androidNotification,
          },
          apns: {
            headers: {
              'apns-priority': '10',
              'apns-push-type': 'alert',
              'apns-collapse-id': id.slice(0, 64),
            },
            payload: {aps: {sound: 'default'}},
            ...(image ? {fcmOptions: {imageUrl: image}} : {}),
          },
        },
      }),
    },
  );
}

function docId(doc) {
  const parts = String(doc.name || '').split('/');
  return parts[parts.length - 1] || '';
}

async function main() {
  const token = loadAccessToken();
  const now = new Date();
  const docs = await listAnnouncements(token);
  const candidates = [];
  let expired = 0;
  let already = 0;
  for (const doc of docs) {
    const id = docId(doc);
    const fields = doc.fields || {};
    const data = toData(fields);
    if (!isTourismEvent(data)) continue;
    if (claimed(fields)) {
      already += 1;
      continue;
    }
    const copy = announcementPushCopy(data, now);
    if (!copy.eligible) {
      if (copy.phase === 'expired') {
        expired += 1;
        console.log(`skip expired  ${data.title}`);
      }
      continue;
    }
    candidates.push({id, copy, title: data.title});
  }
  candidates.sort((a, b) => {
    const rank = (copy) => (copy.phase === 'ongoing' ? 0 : 1);
    const ra = rank(a.copy);
    const rb = rank(b.copy);
    if (ra !== rb) return ra - rb;
    const ta = a.copy.phase === 'ongoing'
      ? (a.copy.endMs ?? Number.MAX_SAFE_INTEGER)
      : (a.copy.startMs ?? Number.MAX_SAFE_INTEGER);
    const tb = b.copy.phase === 'ongoing'
      ? (b.copy.endMs ?? Number.MAX_SAFE_INTEGER)
      : (b.copy.startMs ?? Number.MAX_SAFE_INTEGER);
    return ta - tb;
  });
  console.log(
    `announcements=${docs.length} eligible=${candidates.length} alreadySent=${already} expiredSkipped=${expired} dryRun=${dryRun}`,
  );
  for (const item of candidates) {
    console.log(`${item.copy.phase}  ${item.copy.title}  |  ${item.copy.body}`);
  }
  if (dryRun) return;
  let sent = 0;
  for (const item of candidates.slice(0, BATCH)) {
    await writeClaim(token, item.id, false);
    try {
      await sendTopic(token, item.id, item.copy, true);
      sent += 1;
      console.log(`sent ${item.id}`);
    } catch (err) {
      const message = String(err && err.message || err);
      if (item.copy.imageUrl && message.toLowerCase().includes('image')) {
        await sendTopic(token, item.id, item.copy, false);
        sent += 1;
        console.log(`sent ${item.id} without image`);
        continue;
      }
      await writeClaim(token, item.id, true);
      console.error(`failed ${item.id} ${message.slice(0, 300)}`);
    }
  }
  console.log(`delivered=${sent}`);
}

main().catch((err) => {
  console.error(String(err && err.message || err).slice(0, 500));
  process.exit(1);
});
