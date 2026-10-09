// Supabase Edge Function: send FCM topic push for a new tourism event.
// Topic must match Flutter `kEventsFcmTopic` = "tourism_events".
//
// Secrets (Dashboard → Edge Functions → Secrets, or CLI):
//   FIREBASE_SERVICE_ACCOUNT_JSON  = full JSON of Firebase service account key
//
// Deploy:
//   npx supabase login
//   npx supabase functions deploy notify-tourism-event --project-ref cgpjqkbbmyxvitwpkikn
//   npx supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(Get-Content path\to\sa.json -Raw)" --project-ref cgpjqkbbmyxvitwpkikn
//
// Called by Flutter after creating a Firestore `events` document (Spark-safe).

import * as jose from "https://deno.land/x/jose@v5.2.0/index.ts";

const FCM_TOPIC = "tourism_events";
const FCM_CHANNEL = "tourism_events_channel";
const FIREBASE_PROJECT_FALLBACK = "atmos-trs-system";

type ServiceAccount = {
  project_id?: string;
  client_email: string;
  private_key: string;
};

type EventPayload = {
  eventId?: string;
  title?: string;
  municipality?: string;
  venue?: string;
  description?: string;
  time?: string;
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

/** Parse Firebase SA JSON; tolerate BOM / wrapping quotes / double-encoding. */
function parseServiceAccountJson(raw: string): ServiceAccount {
  let s = raw.trim();
  if (s.charCodeAt(0) === 0xfeff) s = s.slice(1);
  const tryParse = (v: string): ServiceAccount | null => {
    try {
      const parsed = JSON.parse(v);
      if (typeof parsed === "string") {
        return tryParse(parsed);
      }
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
  throw new Error(
    `FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON (starts with: ${s.slice(0, 24)})`,
  );
}

function buildBody(data: EventPayload): string {
  const municipality = String(data.municipality || "").trim();
  const venue = String(data.venue || "").trim();
  const desc = String(data.description || "").trim();
  const time = String(data.time || "").trim();
  const lines: string[] = [];
  const location = [municipality, venue].filter(Boolean).join(" · ");
  if (location) lines.push(location);
  if (time) lines.push(time);
  if (desc) lines.push(desc);
  if (lines.length === 0) return "Open the app to see details.";
  let body = lines.join("\n");
  if (body.length > 280) body = `${body.slice(0, 277)}…`;
  return body;
}

/** Verify Firebase ID token via JWKS (works for web + long claim tokens). */
async function assertStaffFirebaseUser(
  idToken: string,
  projectId: string,
): Promise<void> {
  const JWKS = jose.createRemoteJWKSet(
    new URL(
      "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
    ),
  );
  let payload: jose.JWTPayload;
  try {
    const verified = await jose.jwtVerify(idToken, JWKS, {
      issuer: `https://securetoken.google.com/${projectId}`,
      audience: projectId,
    });
    payload = verified.payload;
  } catch (e) {
    const detail = e instanceof Error ? e.message : String(e);
    throw new Error(`Invalid Firebase ID token (${detail})`);
  }

  const staff =
    payload.staff === true ||
    payload.staff === "true" ||
    payload.admin === true ||
    payload.admin === "true";
  const role = String(payload.role || "").toLowerCase();
  const staffRole = [
    "admin",
    "administrator",
    "governor",
    "municipal_manager",
    "manager",
  ].includes(role);
  if (!staff && !staffRole) {
    throw new Error("Only staff accounts may send event push notifications");
  }
}

async function getGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const pem = sa.private_key.replace(/\\n/g, "\n");
  const key = await jose.importPKCS8(pem, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const jwt = await new jose.SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
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
    throw new Error(
      `Google token exchange failed: ${JSON.stringify(tokenJson)}`,
    );
  }
  return String(tokenJson.access_token);
}

async function sendFcmTopic(
  accessToken: string,
  projectId: string,
  data: EventPayload,
): Promise<string> {
  const eventTitle = String(data.title || "New event").trim() || "New event";
  const body = buildBody(data);
  const municipality = String(data.municipality || "").trim();
  const venue = String(data.venue || "").trim();
  const description = String(data.description || "").trim();
  const timeStr = String(data.time || "").trim();
  const eventId = String(data.eventId || "");

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          topic: FCM_TOPIC,
          notification: {
            title: `New event: ${eventTitle}`,
            body,
          },
          data: {
            type: "new_event",
            eventId,
            title: eventTitle,
            municipality,
            venue,
            time: timeStr,
            description,
            notificationBody: body,
          },
          android: {
            priority: "high",
            notification: {
              channelId: FCM_CHANNEL,
              sound: "default",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
        },
      }),
    },
  );
  const json = await res.json();
  if (!res.ok) {
    throw new Error(`FCM send failed: ${JSON.stringify(json)}`);
  }
  return String(json.name || "ok");
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
          message:
            "Set FIREBASE_SERVICE_ACCOUNT_JSON in Supabase Edge Function secrets.",
        },
        500,
      );
    }
    const sa = parseServiceAccountJson(saRaw);
    const projectId =
      sa.project_id?.trim() || FIREBASE_PROJECT_FALLBACK;

    const firebaseAuth =
      req.headers.get("x-firebase-auth") ||
      req.headers.get("X-Firebase-Auth") ||
      "";
    if (!firebaseAuth) {
      return jsonResponse(
        { error: "unauthenticated", message: "Missing X-Firebase-Auth header" },
        401,
      );
    }
    await assertStaffFirebaseUser(firebaseAuth, projectId);

    const payload = (await req.json()) as EventPayload;
    if (!String(payload.title || "").trim() && !String(payload.eventId || "").trim()) {
      return jsonResponse(
        { error: "invalid_argument", message: "Provide title or eventId" },
        400,
      );
    }

    const accessToken = await getGoogleAccessToken(sa);
    const messageName = await sendFcmTopic(accessToken, projectId, payload);

    return jsonResponse({
      ok: true,
      topic: FCM_TOPIC,
      messageName,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error("notify-tourism-event failed", message);
    const status = message.includes("Only staff") ||
        message.includes("Invalid Firebase") ||
        message.includes("audience")
      ? 403
      : 500;
    return jsonResponse({ error: "failed", message }, status);
  }
});
