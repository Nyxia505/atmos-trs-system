const functions = require("firebase-functions/v1");
const https = require("https");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const ADMIN_ROLES = new Set([
  "admin",
  "administrator",
  "governor",
]);

const MANAGER_ROLES = new Set([
  "municipal_manager",
  "municipalmanager",
  "manager",
]);

function normalizeRole(raw) {
  return String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "_");
}

function roleClaims(role) {
  const normalized = normalizeRole(role);
  const isAdmin = ADMIN_ROLES.has(normalized);
  const isManager = MANAGER_ROLES.has(normalized);
  const isStaff = isAdmin || isManager;
  return {
    role: normalized || "tourist",
    admin: isAdmin,
    municipal_manager: isManager,
    staff: isStaff,
    rolePermanent: isStaff,
  };
}

async function applyRoleClaimsForUid(uid, role) {
  if (!uid) return;
  const claims = roleClaims(role);
  try {
    await admin.auth().setCustomUserClaims(uid, claims);
    console.log("syncUserRoleClaims", uid, claims);
  } catch (e) {
    console.error("syncUserRoleClaims failed", uid, e);
  }
}

/**
 * Keeps Firebase Auth custom claims in sync with users/{uid}.role so Firestore
 * rules see permanent staff/admin flags (request.auth.token.staff / .admin).
 */
exports.syncUserRoleClaims = functions.firestore
  .document("users/{userId}")
  .onWrite(async (change, context) => {
    const uid = context.params.userId;
    const after = change.after.exists ? change.after.data() : null;
    if (!after) {
      try {
        await admin.auth().setCustomUserClaims(uid, {
          role: "tourist",
          admin: false,
          municipal_manager: false,
          staff: false,
        });
      } catch (e) {
        console.error("clearUserRoleClaims failed", uid, e);
      }
      return null;
    }

    const docUid = String(after.firebaseUid || after.firebase_uid || uid).trim();
    const targetUid = docUid || uid;
    const permanent = after.rolePermanent === true;
    const role = String(after.role || "").trim();
    if (permanent && !role) {
      return null;
    }
    await applyRoleClaimsForUid(targetUid, role);
    return null;
  });

/**
 * Callable: refresh Auth custom claims from `users/{uid}` (long-term admin/staff).
 * Call after login so Firestore rules see token.admin / token.staff immediately.
 */
const LISTED_ADMIN_EMAILS = new Set(["optaca@gmail.com"]);

exports.refreshRoleClaims = functions.https.onCall(async (_data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in first.",
    );
  }
  const uid = context.auth.uid;
  const email = (context.auth.token.email || "").trim().toLowerCase();
  let role = "tourist";
  let rolePermanent = false;
  try {
    const snap = await admin.firestore().collection("users").doc(uid).get();
    if (snap.exists && snap.data()) {
      const data = snap.data();
      rolePermanent = data.rolePermanent === true;
      if (rolePermanent && data.role) {
        role = String(data.role);
      } else if (data.role) {
        role = String(data.role);
      }
    }
  } catch (e) {
    console.error("refreshRoleClaims read users", uid, e);
  }

  const normalized = normalizeRole(role);
  if (ADMIN_ROLES.has(normalized) || MANAGER_ROLES.has(normalized)) {
    rolePermanent = true;
  }

  if (LISTED_ADMIN_EMAILS.has(email)) {
    role = "admin";
    rolePermanent = true;
    try {
      await admin.firestore().collection("users").doc(uid).set(
        {
          email: context.auth.token.email || email,
          emailLower: email,
          role: "admin",
          rolePermanent: true,
          firebaseUid: uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      const docId = email
        .replace(/@/g, "_at_")
        .replace(/\./g, "_")
        .replace(/[^a-z0-9_]+/g, "");
      await admin.firestore().collection("admin_accounts").doc(docId).set(
        {
          email: context.auth.token.email || email,
          emailLower: email,
          role: "admin",
          active: true,
          firebaseUid: uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    } catch (e) {
      console.error("refreshRoleClaims persist listed admin", uid, e);
      throw new functions.https.HttpsError(
        "internal",
        "Could not persist admin profile.",
      );
    }
  }

  try {
    await applyRoleClaimsForUid(uid, role);
  } catch (e) {
    console.error("refreshRoleClaims setCustomUserClaims", uid, e);
    throw new functions.https.HttpsError(
      "internal",
      "Could not refresh Auth role claims.",
    );
  }
  return { ok: true, uid, rolePermanent, ...roleClaims(role) };
});

/** Must match Flutter [kEventsFcmTopic] — devices subscribe to receive new-event alerts. */
const EVENTS_FCM_TOPIC = "tourism_events";

const EVENT_MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

function formatEventDateWords(d) {
  return `${EVENT_MONTH_NAMES[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
}

function formatEventTime12(d) {
  let h = d.getHours();
  const m = d.getMinutes();
  const period = h >= 12 ? "PM" : "AM";
  h = h % 12;
  if (h === 0) h = 12;
  const mm = m < 10 ? `0${m}` : `${m}`;
  return `${h}:${mm} ${period}`;
}

function formatEventDateTimeDisplay(d) {
  return `${formatEventDateWords(d)} · ${formatEventTime12(d)}`;
}

/** Push body: municipality · venue, then date · time, then description. */
function buildEventPushNotificationBody(data) {
  const municipality = String(data.municipality || "").trim();
  const venue = String(data.venue || "").trim();
  const desc = String(data.description || "").trim();
  const lines = [];
  const location = [municipality, venue].filter(Boolean).join(" · ");
  if (location) lines.push(location);
  if (data.startAt && typeof data.startAt.toDate === "function") {
    lines.push(formatEventDateTimeDisplay(data.startAt.toDate()));
  }
  if (desc) lines.push(desc);
  if (lines.length === 0) return "Open the app to see details.";
  let body = lines.join("\n");
  if (body.length > 280) body = `${body.slice(0, 277)}…`;
  return body;
}

function setCorsHeaders(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.setHeader("Access-Control-Max-Age", "86400");
}

/** Decode Google encoded polyline to array of [lat, lng] (in degrees). */
function decodePolyline(encoded) {
  const points = [];
  let index = 0;
  let lat = 0;
  let lng = 0;
  while (index < encoded.length) {
    let b, shift = 0, result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    const dlat = (result & 1) ? ~(result >> 1) : (result >> 1);
    lat += dlat;
    shift = 0;
    result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    const dlng = (result & 1) ? ~(result >> 1) : (result >> 1);
    lng += dlng;
    points.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return points;
}

function runDirectionsProxy(origin, destination, waypoints, apiKey) {
  const params = new URLSearchParams({
    origin,
    destination,
    mode: "driving",
    key: apiKey,
  });
  if (waypoints && String(waypoints).trim()) {
    params.set("waypoints", waypoints);
  }
  const url = `https://maps.googleapis.com/maps/api/directions/json?${params.toString()}`;
  return new Promise((resolve) => {
    https
      .get(url, (res) => {
        let body = "";
        res.on("data", (chunk) => (body += chunk));
        res.on("end", () => {
          try {
            const json = JSON.parse(body);
            if (json.status !== "OK") {
              return resolve({
                error: json.status || "UNKNOWN",
                errorMessage: json.error_message || null,
              });
            }
            const routes = json.routes;
            if (!routes || routes.length === 0) {
              return resolve({ error: "ZERO_RESULTS" });
            }
            const route = routes[0];
            const legs = route.legs;
            const points = [];
            if (legs && legs.length > 0) {
              for (const leg of legs) {
                const steps = leg.steps;
                if (!steps) continue;
                for (const step of steps) {
                  const pl = step.polyline && step.polyline.points;
                  if (pl) {
                    const decoded = decodePolyline(pl);
                    for (const p of decoded) {
                      const last = points[points.length - 1];
                      if (last && last.lat === p.lat && last.lng === p.lng) continue;
                      points.push(p);
                    }
                  }
                }
              }
            }
            if (points.length === 0) {
              const overview = route.overview_polyline;
              const encoded = overview && overview.points;
              if (!encoded) return resolve({ error: "NO_POLYLINE" });
              return resolve({ encodedPolyline: encoded });
            }
            resolve({ points });
          } catch (e) {
            resolve({
              error: "INTERNAL",
              errorMessage: e.message || String(e),
            });
          }
        });
      })
      .on("error", (err) => {
        resolve({
          error: "INTERNAL",
          errorMessage: err.message || String(err),
        });
      });
  });
}

/**
 * HTTP Cloud Function with CORS for web (localhost and production).
 * POST body: JSON { origin, destination, waypoints?, apiKey }
 * Response: JSON { encodedPolyline } or { error, errorMessage }
 */
exports.getDirectionsHttp = functions.https.onRequest(async (req, res) => {
  setCorsHeaders(res);
  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }
  if (req.method !== "POST") {
    res.status(405).json({ error: "METHOD_NOT_ALLOWED" });
    return;
  }
  try {
    const data = req.body?.data != null ? req.body.data : req.body;
    const { origin, destination, waypoints = "", apiKey } = data || {};
    if (!origin || !destination || !apiKey) {
      res.status(400).json({
        error: "invalid-argument",
        errorMessage: "Missing origin, destination, or apiKey",
      });
      return;
    }
    const result = await runDirectionsProxy(origin, destination, waypoints, apiKey);
    res.status(200).json(result);
  } catch (e) {
    res.status(500).json({
      error: "INTERNAL",
      errorMessage: e.message || e.stack || String(e),
    });
  }
});

/**
 * Callable Cloud Function that proxies Google Directions API.
 * Used by Flutter web to avoid CORS (browser blocks direct calls to maps.googleapis.com).
 *
 * Request: { origin, destination, waypoints?, apiKey }
 *   - origin: "lat,lng"
 *   - destination: "lat,lng"
 *   - waypoints: "lat,lng|lat,lng|..." (optional, max 25)
 *   - apiKey: your Google Maps API key (with Directions API enabled)
 *
 * Response: { encodedPolyline } or { error, errorMessage }
 */
exports.getDirections = functions.https.onCall(async (data, context) => {
  try {
    const { origin, destination, waypoints = "", apiKey } = data || {};
    if (!origin || !destination || !apiKey) {
      return {
        error: "invalid-argument",
        errorMessage: "Missing origin, destination, or apiKey",
      };
    }
    return runDirectionsProxy(origin, destination, waypoints, apiKey);
  } catch (e) {
    return {
      error: "INTERNAL",
      errorMessage: e.message || e.stack || String(e),
    };
  }
});

/**
 * Send FCM topic message for a newly published tourism event.
 * Shared by Firestore onCreate + callable (admin save path).
 */
async function sendTourismEventTopicPush(eventId, data) {
  const eventTitle = String(data.title || "New event").trim() || "New event";
  const municipality = String(data.municipality || "").trim();
  const venue = String(data.venue || "").trim();
  const description = String(data.description || "").trim();
  const body = buildEventPushNotificationBody(data);
  let timeStr = "";
  if (data.startAt && typeof data.startAt.toDate === "function") {
    timeStr = formatEventDateTimeDisplay(data.startAt.toDate());
  } else if (typeof data.time === "string" && data.time.trim()) {
    timeStr = data.time.trim();
  }
  const messageId = await admin.messaging().send({
    topic: EVENTS_FCM_TOPIC,
    notification: {
      title: `New event: ${eventTitle}`,
      body,
    },
    data: {
      type: "new_event",
      eventId: String(eventId || ""),
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
        channelId: "tourism_events_channel",
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
  });
  console.log("tourism_events push sent", {
    eventId,
    messageId,
    topic: EVENTS_FCM_TOPIC,
    title: eventTitle,
  });
  return messageId;
}

/**
 * When an admin creates a new document in `events`, notify all devices subscribed
 * to the `tourism_events` FCM topic (see Flutter `initPushNotifications`).
 * Edits to existing events do not trigger this (only onCreate).
 */
exports.notifyNewTourismEvent = functions.firestore
  .document("events/{eventId}")
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const eventId = context.params.eventId;
    console.log("notifyNewTourismEvent onCreate", eventId, data.title || "");
    try {
      await sendTourismEventTopicPush(eventId, data);
    } catch (e) {
      console.error("notifyNewTourismEvent FCM send failed", e);
    }
  });

/**
 * Callable backup: admin app can request a topic push right after saving a new
 * event (covers cases where the client wants an immediate send confirmation).
 * Staff/admin only. Safe to call even if onCreate also fired (rare duplicate).
 */
exports.broadcastTourismEventPush = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in required to send event push notifications."
    );
  }
  const token = context.auth.token || {};
  const staff =
    token.staff === true ||
    token.staff === "true" ||
    token.admin === true ||
    token.admin === "true" ||
    ADMIN_ROLES.has(normalizeRole(token.role)) ||
    MANAGER_ROLES.has(normalizeRole(token.role));
  if (!staff) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only staff can broadcast event push notifications."
    );
  }

  const eventId = String((data && data.eventId) || "").trim();
  let payload = data || {};
  if (eventId) {
    const snap = await admin.firestore().collection("events").doc(eventId).get();
    if (snap.exists) {
      payload = { ...snap.data(), ...payload };
    }
  }
  if (!String(payload.title || "").trim() && !eventId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Provide eventId or title for the push notification."
    );
  }

  try {
    const messageId = await sendTourismEventTopicPush(eventId, payload);
    return { ok: true, messageId, topic: EVENTS_FCM_TOPIC };
  } catch (e) {
    console.error("broadcastTourismEventPush failed", e);
    throw new functions.https.HttpsError(
      "internal",
      e.message || "FCM send failed"
    );
  }
});

const {
  uploadTransportationFees,
} = require("./seed-transportation-fees-once");
const {
  uploadHubSpotTransportFees,
} = require("./seed-hub-spot-transport-fees-once");
const { seedDefaultAdminAccount } = require("./seed-default-admin-account");

/**
 * Callable (admin/staff): creates/updates `transportation_fees` (272 routes).
 * Firebase Console → Functions → seedTransportationFees, or admin app button.
 */
exports.seedTransportationFees = functions.https.onCall(async (_data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in as admin or staff.",
    );
  }
  const token = context.auth.token || {};
  if (!token.admin && !token.staff) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Admin or staff role required.",
    );
  }
  const count = await uploadTransportationFees();
  return { collection: "transportation_fees", uploaded: count };
});

/** One-time HTTP seed (Admin SDK). DELETE after collection exists. */
const SEED_HTTP_KEY =
  process.env.SEED_TRANSPORTATION_FEES_KEY || "atmos-mo-fares-2026";

exports.seedTransportationFeesHttp = functions.https.onRequest(
  async (req, res) => {
    const key = req.query.key || req.get("x-seed-key");
    if (key !== SEED_HTTP_KEY) {
      res.status(403).json({ error: "invalid or missing key" });
      return;
    }
    try {
      const count = await uploadTransportationFees();
      res.status(200).json({
        collection: "transportation_fees",
        uploaded: count,
        project: "atmos-trs-system",
      });
    } catch (e) {
      console.error("seedTransportationFeesHttp", e);
      res.status(500).json({ error: String(e) });
    }
  },
);

/** Callable (admin/staff): hub ↔ tourist spot fares (28 legs). */
exports.seedHubSpotTransportFees = functions.https.onCall(async (_data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in as admin or staff.",
    );
  }
  const token = context.auth.token || {};
  if (!token.admin && !token.staff) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Admin or staff role required.",
    );
  }
  const count = await uploadHubSpotTransportFees();
  return { collection: "hub_spot_transport_fees", uploaded: count };
});

/** One-time HTTP seed for hub_spot_transport_fees (Admin SDK). */
exports.seedHubSpotTransportFeesHttp = functions.https.onRequest(
  async (req, res) => {
    const key = req.query.key || req.get("x-seed-key");
    if (key !== SEED_HTTP_KEY) {
      res.status(403).json({ error: "invalid or missing key" });
      return;
    }
    try {
      const count = await uploadHubSpotTransportFees();
      res.status(200).json({
        collection: "hub_spot_transport_fees",
        uploaded: count,
        project: "atmos-trs-system",
      });
    } catch (e) {
      console.error("seedHubSpotTransportFeesHttp", e);
      res.status(500).json({ error: String(e) });
    }
  },
);

/** One-time: Auth user + admin_accounts + users/{uid} for OPTACA@gmail.com */
exports.seedDefaultAdminAccountHttp = functions.https.onRequest(async (req, res) => {
  const key = req.query.key || req.get("x-seed-key");
  if (key !== SEED_HTTP_KEY) {
    res.status(403).json({ error: "invalid or missing key" });
    return;
  }
  try {
    const result = await seedDefaultAdminAccount();
    res.status(200).json({ ok: true, project: "atmos-trs-system", ...result });
  } catch (e) {
    console.error("seedDefaultAdminAccountHttp", e);
    res.status(500).json({ error: String(e) });
  }
});
