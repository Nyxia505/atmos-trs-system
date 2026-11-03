// Sends one FCM message to the ATMOS tourist app topic `governor_announcements`.
// The installed APK (com.atmos.trs) already subscribes to that topic and opens
// `data.announcementId`. This does not write event title, dates, or images.
//
// Secret: FIREBASE_SERVICE_ACCOUNT_JSON (same key as notify-tourism-event).
// Deploy:
//   npx supabase functions deploy notify-lgu-event --project-ref cgpjqkbbmyxvitwpkikn

import * as jose from "https://deno.land/x/jose@v5.2.0/index.ts";

const TOPIC = "governor_announcements";
const CHANNEL = "atmos_announcement_heads_up";
const PROJECT_FALLBACK = "atmos-trs-system";
const BATCH = 20;
const STAFF = new Set([
  "governor",
  "tourism",
  "tourism_office",
  "provincial_tourism",
  "tourism_province",
]);

type ServiceAccount = {
  project_id?: string;
  client_email: string;
  private_key: string;
};

type FsValue = {
  stringValue?: string;
  booleanValue?: boolean;
  integerValue?: string;
  doubleValue?: number;
  timestampValue?: string;
  nullValue?: null;
  arrayValue?: { values?: FsValue[] };
  mapValue?: { fields?: Record<string, FsValue> };
};

type FsDoc = {
  name?: string;
  fields?: Record<string, FsValue>;
};

type PushCopy = {
  phase: string;
  title: string;
  body: string;
  type: string;
  imageUrl: string;
  location: string;
  eventDate: string;
  notificationType: string;
  eligible: boolean;
  startMs: number | null;
  endMs: number | null;
  tourismEvent: boolean;
};

function corsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-firebase-auth",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json" },
  });
}

function parseServiceAccountJson(raw: string): ServiceAccount {
  let s = raw.trim();
  if (s.charCodeAt(0) === 0xfeff) s = s.slice(1);
  const tryParse = (v: string): ServiceAccount | null => {
    try {
      const parsed = JSON.parse(v);
      if (typeof parsed === "string") return tryParse(parsed);
      if (parsed && typeof parsed === "object" && parsed.client_email) {
        return parsed as ServiceAccount;
      }
      return null;
    } catch {
      return null;
    }
  };
  let sa = tryParse(s);
  if (sa) return sa;
  if (
    (s.startsWith('"') && s.endsWith('"')) ||
    (s.startsWith("'") && s.endsWith("'"))
  ) {
    sa = tryParse(s.slice(1, -1));
    if (sa) return sa;
  }
  sa = tryParse(s.replace(/\\"/g, '"').replace(/\\\\/g, "\\"));
  if (sa) return sa;
  throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON");
}

function normRole(value: string): string {
  return value.trim().toLowerCase().replace(/\s+/g, "_");
}

function str(fields: Record<string, FsValue> | undefined, key: string): string {
  const value = fields?.[key];
  if (!value || value.nullValue !== undefined) return "";
  return String(value.stringValue || "").trim();
}

function bool(fields: Record<string, FsValue> | undefined, key: string): boolean {
  return fields?.[key]?.booleanValue === true;
}

function intOf(fields: Record<string, FsValue> | undefined, key: string): number | null {
  const raw = fields?.[key];
  if (!raw) return null;
  if (raw.integerValue != null) {
    const n = Number(raw.integerValue);
    return Number.isFinite(n) ? n : null;
  }
  if (typeof raw.doubleValue === "number") return raw.doubleValue;
  return null;
}

function timeMs(fields: Record<string, FsValue> | undefined, key: string): number | null {
  const raw = fields?.[key]?.timestampValue;
  if (!raw) return null;
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? ms : null;
}

function strings(fields: Record<string, FsValue> | undefined, key: string): string[] {
  const values = fields?.[key]?.arrayValue?.values || [];
  return values
    .map((item) => String(item.stringValue || "").trim())
    .filter(Boolean);
}

function claimed(fields: Record<string, FsValue> | undefined): boolean {
  const value = fields?.fcmSent_published;
  if (!value || value.nullValue !== undefined) return false;
  return true;
}

function docId(doc: FsDoc): string {
  const name = String(doc.name || "");
  const parts = name.split("/");
  return parts[parts.length - 1] || "";
}

function plain(value: string): string {
  return value.replace(/\*\*(.+?)\*\*/g, "$1").replace(/\s+/g, " ").trim();
}

function dateOnlyMs(value: string): number | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  return Date.UTC(year, month - 1, day, 0, 0, 0) - 8 * 60 * 60 * 1000;
}

function windowOf(fields: Record<string, FsValue> | undefined): {
  startMs: number | null;
  endMs: number | null;
} {
  const start = timeMs(fields, "startsAt") ??
    timeMs(fields, "startDate") ??
    timeMs(fields, "eventStart");
  const dateOnly = dateOnlyMs(str(fields, "date"));
  const startMs = start ?? dateOnly;
  let endMs = timeMs(fields, "endsAt") ??
    timeMs(fields, "endDate") ??
    timeMs(fields, "eventEnd");
  if (endMs == null && startMs != null) {
    const days = intOf(fields, "durationDays");
    const span = days != null && days >= 1 ? Math.min(days, 60) : 1;
    endMs = startMs + span * 24 * 60 * 60 * 1000;
  }
  return { startMs, endMs };
}

function classify(fields: Record<string, FsValue> | undefined, nowMs: number): string {
  const status = str(fields, "status").toLowerCase();
  if (status === "rejected" || status === "draft" || status === "pending") {
    return "skip";
  }
  if (!plain(str(fields, "title"))) return "skip";
  if (str(fields, "scheduleState").toLowerCase() === "expired") return "expired";
  const { startMs, endMs } = windowOf(fields);
  if (endMs != null && nowMs >= endMs) return "expired";
  if (startMs != null && nowMs < startMs) return "upcoming";
  if (startMs != null) return "ongoing";
  if (bool(fields, "published") || str(fields, "scheduleState").toLowerCase() === "live") {
    return "ongoing";
  }
  return "skip";
}

function isTourismEvent(fields: Record<string, FsValue> | undefined): boolean {
  const type = str(fields, "type").toLowerCase();
  if (type === "event") return true;
  return !!(
    fields?.startsAt ||
    fields?.endsAt ||
    (fields?.scheduleState && fields.scheduleState.nullValue === undefined)
  );
}

function longDate(ms: number | null): string {
  if (ms == null) return "";
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Manila",
    month: "long",
    day: "numeric",
    year: "numeric",
  }).format(new Date(ms));
}

function httpsImage(fields: Record<string, FsValue> | undefined): string {
  const candidates = [str(fields, "imageUrl"), ...strings(fields, "imageUrls")];
  for (const url of candidates) {
    if (url.startsWith("https://") || url.startsWith("http://")) {
      return url.slice(0, 500);
    }
  }
  return "";
}

function pushCopy(fields: Record<string, FsValue> | undefined, nowMs: number): PushCopy {
  const tourismEvent = isTourismEvent(fields);
  const phase = classify(fields, nowMs);
  const rawTitle = plain(str(fields, "title")) || "Event";
  const place = str(fields, "location") || str(fields, "municipalityName");
  const { startMs, endMs } = windowOf(fields);
  const when = startMs != null ? longDate(startMs) : str(fields, "date");
  const imageUrl = httpsImage(fields);
  if (!tourismEvent) {
    const desc = plain(str(fields, "content") || str(fields, "message"));
    return {
      phase: "ongoing",
      title: rawTitle.slice(0, 120),
      body: (desc || "New announcement").slice(0, 200),
      type: str(fields, "type") || "General",
      imageUrl,
      location: "",
      eventDate: "",
      notificationType: str(fields, "type") || "General",
      eligible: bool(fields, "published"),
      startMs,
      endMs,
      tourismEvent: false,
    };
  }
  const prefix = phase === "ongoing" ? "Ongoing Event" : "Upcoming Event";
  let title = `${prefix}: ${rawTitle}`;
  if (title.length > 120) title = `${title.slice(0, 117)}...`;
  const desc = plain(str(fields, "content") || str(fields, "message"));
  let body: string;
  if (desc) {
    body = desc.length > 140 ? `${desc.slice(0, 137)}...` : desc;
    const extras: string[] = [];
    if (place && !body.toLowerCase().includes(place.toLowerCase())) extras.push(place);
    if (when && !body.includes(when)) extras.push(when);
    if (extras.length) body = `${body} — ${extras.join(" · ")}`;
  } else if (place && when) {
    body = `Join the ${rawTitle} in ${place} on ${when}!`;
  } else {
    body = [place, when].filter(Boolean).join(" · ") || rawTitle;
  }
  if (body.length > 200) body = `${body.slice(0, 197)}...`;
  return {
    phase,
    title,
    body,
    type: str(fields, "type") || "Event",
    imageUrl,
    location: place.slice(0, 120),
    eventDate: when.slice(0, 80),
    notificationType: "tourism_event",
    eligible: phase === "upcoming" || phase === "ongoing",
    startMs,
    endMs,
    tourismEvent: true,
  };
}

async function googleAccessToken(sa: ServiceAccount): Promise<string> {
  const pem = sa.private_key.replace(/\\n/g, "\n");
  const key = await jose.importPKCS8(pem, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const jwt = await new jose.SignJWT({
    scope: [
      "https://www.googleapis.com/auth/firebase.messaging",
      "https://www.googleapis.com/auth/datastore",
    ].join(" "),
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const tokenJson = await tokenRes.json();
  if (!tokenRes.ok || !tokenJson.access_token) {
    throw new Error(`Google token exchange failed: ${JSON.stringify(tokenJson)}`);
  }
  return String(tokenJson.access_token);
}

async function verifyFirebaseUser(
  idToken: string,
  projectId: string,
): Promise<{ uid: string; role: string }> {
  const JWKS = jose.createRemoteJWKSet(
    new URL(
      "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
    ),
  );
  const verified = await jose.jwtVerify(idToken, JWKS, {
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
  });
  const payload = verified.payload;
  const uid = String(payload.sub || payload.user_id || "");
  return { uid, role: normRole(String(payload.role || "")) };
}

function firestoreRoot(projectId: string): string {
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
}

async function firestoreGet(
  token: string,
  projectId: string,
  path: string,
): Promise<FsDoc | null> {
  const res = await fetch(`${firestoreRoot(projectId)}/${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 404) return null;
  const json = await res.json();
  if (!res.ok) {
    throw new Error(`Firestore read failed: ${JSON.stringify(json)}`);
  }
  return json as FsDoc;
}

async function assertStaff(
  idToken: string,
  projectId: string,
  accessToken: string,
): Promise<void> {
  let uid = "";
  let role = "";
  try {
    const user = await verifyFirebaseUser(idToken, projectId);
    uid = user.uid;
    role = user.role;
  } catch (e) {
    const detail = e instanceof Error ? e.message : String(e);
    throw new Error(`Invalid Firebase ID token (${detail})`);
  }
  if (!STAFF.has(role) && uid) {
    const profile = await firestoreGet(accessToken, projectId, `users/${uid}`);
    role = normRole(str(profile?.fields, "role"));
  }
  if (!STAFF.has(role)) {
    throw new Error("Only staff accounts may send event push notifications");
  }
}

async function listAnnouncements(
  token: string,
  projectId: string,
): Promise<FsDoc[]> {
  const docs: FsDoc[] = [];
  let pageToken = "";
  while (docs.length < 300) {
    const url = new URL(`${firestoreRoot(projectId)}/announcements`);
    url.searchParams.set("pageSize", "100");
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    const json = await res.json();
    if (!res.ok) {
      throw new Error(`Firestore list failed: ${JSON.stringify(json)}`);
    }
    docs.push(...((json.documents || []) as FsDoc[]));
    pageToken = String(json.nextPageToken || "");
    if (!pageToken) break;
  }
  return docs;
}

async function writeClaim(
  token: string,
  projectId: string,
  id: string,
  clear: boolean,
): Promise<void> {
  const name =
    `projects/${projectId}/databases/(default)/documents/announcements/${id}`;
  const now = new Date().toISOString();
  const fields: Record<string, FsValue> = clear
    ? {}
    : {
      fcmSent_published: { timestampValue: now },
      fcmSentAt: { timestampValue: now },
    };
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        writes: [
          {
            update: { name, fields },
            updateMask: {
              fieldPaths: clear
                ? ["fcmSent_published", "fcmSentAt"]
                : ["fcmSent_published", "fcmSentAt"],
            },
            currentDocument: { exists: true },
          },
        ],
      }),
    },
  );
  const json = await res.json();
  if (!res.ok) {
    throw new Error(`Firestore claim failed: ${JSON.stringify(json)}`);
  }
}

async function sendTopic(
  token: string,
  projectId: string,
  id: string,
  copy: PushCopy,
  includeImage: boolean,
): Promise<void> {
  const data: Record<string, string> = {
    type: copy.type || "Event",
    announcementId: id,
    eventType: copy.type || "Event",
    title: copy.title,
    body: copy.body,
    notificationType: copy.notificationType || "tourism_event",
    eventId: id,
    location: copy.location || "",
    eventDate: copy.eventDate || "",
  };
  const image = includeImage ? copy.imageUrl : "";
  if (image) data.imageUrl = image;
  const notification: Record<string, string> = {
    title: copy.title,
    body: copy.body,
  };
  if (image) notification.image = image;
  const androidNotification: Record<string, string> = {
    channelId: CHANNEL,
    sound: "default",
    tag: id,
  };
  if (image) androidNotification.image = image;
  const message: Record<string, unknown> = {
    topic: TOPIC,
    notification,
    data,
    android: {
      priority: "HIGH",
      ttl: "604800s",
      collapseKey: id,
      notification: androidNotification,
    },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-push-type": "alert",
        "apns-collapse-id": id.slice(0, 64),
      },
      payload: { aps: { sound: "default" } },
      ...(image ? { fcmOptions: { imageUrl: image } } : {}),
    },
  };
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ message }),
    },
  );
  const json = await res.json();
  if (!res.ok) {
    throw new Error(`FCM send failed: ${JSON.stringify(json)}`);
  }
}

async function deliver(
  token: string,
  projectId: string,
  id: string,
  copy: PushCopy,
): Promise<void> {
  await writeClaim(token, projectId, id, false);
  try {
    await sendTopic(token, projectId, id, copy, true);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (copy.imageUrl && message.toLowerCase().includes("image")) {
      await sendTopic(token, projectId, id, copy, false);
      return;
    }
    await writeClaim(token, projectId, id, true);
    throw e;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  try {
    const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!saRaw) {
      return jsonResponse(
        {
          error: "missing_secret",
          message: "Set FIREBASE_SERVICE_ACCOUNT_JSON in Supabase Edge Function secrets.",
        },
        500,
      );
    }
    const sa = parseServiceAccountJson(saRaw);
    const projectId = sa.project_id?.trim() || PROJECT_FALLBACK;
    const firebaseAuth = req.headers.get("x-firebase-auth") ||
      req.headers.get("X-Firebase-Auth") ||
      "";
    if (!firebaseAuth) {
      return jsonResponse(
        { error: "unauthenticated", message: "Missing X-Firebase-Auth header" },
        401,
      );
    }
    const accessToken = await googleAccessToken(sa);
    await assertStaff(firebaseAuth, projectId, accessToken);

    const body = await req.json().catch(() => ({})) as {
      announcementId?: string;
      mode?: string;
    };
    const nowMs = Date.now();

    if (body.mode === "backfill") {
      const docs = await listAnnouncements(accessToken, projectId);
      const candidates: { id: string; copy: PushCopy }[] = [];
      let expired = 0;
      for (const doc of docs) {
        const id = docId(doc);
        if (!id || claimed(doc.fields)) continue;
        if (!isTourismEvent(doc.fields)) continue;
        const copy = pushCopy(doc.fields, nowMs);
        if (!copy.eligible) {
          if (copy.phase === "expired") expired += 1;
          continue;
        }
        candidates.push({ id, copy });
      }
      candidates.sort((a, b) => {
        const rank = (copy: PushCopy) => (copy.phase === "ongoing" ? 0 : 1);
        const ra = rank(a.copy);
        const rb = rank(b.copy);
        if (ra !== rb) return ra - rb;
        const ta = a.copy.phase === "ongoing"
          ? (a.copy.endMs ?? Number.MAX_SAFE_INTEGER)
          : (a.copy.startMs ?? Number.MAX_SAFE_INTEGER);
        const tb = b.copy.phase === "ongoing"
          ? (b.copy.endMs ?? Number.MAX_SAFE_INTEGER)
          : (b.copy.startMs ?? Number.MAX_SAFE_INTEGER);
        return ta - tb;
      });
      let sent = 0;
      for (const item of candidates.slice(0, BATCH)) {
        try {
          await deliver(accessToken, projectId, item.id, item.copy);
          sent += 1;
        } catch (e) {
          console.error("backfill send failed", item.id, e instanceof Error ? e.message : e);
        }
      }
      return jsonResponse({
        ok: true,
        topic: TOPIC,
        eligible: candidates.length,
        sent,
        expiredSkipped: expired,
      });
    }

    const announcementId = String(body.announcementId || "").trim();
    if (!announcementId) {
      return jsonResponse(
        { error: "invalid_argument", message: "announcementId is required" },
        400,
      );
    }
    const doc = await firestoreGet(
      accessToken,
      projectId,
      `announcements/${announcementId}`,
    );
    if (!doc) {
      return jsonResponse(
        { error: "not_found", message: "Announcement was not saved." },
        404,
      );
    }
    if (claimed(doc.fields)) {
      return jsonResponse({ ok: true, topic: TOPIC, skipped: true, reason: "already_sent" });
    }
    const copy = pushCopy(doc.fields, nowMs);
    if (!copy.eligible) {
      return jsonResponse({
        ok: true,
        topic: TOPIC,
        skipped: true,
        reason: copy.phase === "expired" ? "expired" : "not_eligible",
      });
    }
    await deliver(accessToken, projectId, announcementId, copy);
    return jsonResponse({ ok: true, topic: TOPIC, skipped: false });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error("notify-lgu-event failed", message);
    const status = message.includes("Only staff") || message.includes("Invalid Firebase")
      ? 403
      : 500;
    return jsonResponse({ error: "failed", message }, status);
  }
});
