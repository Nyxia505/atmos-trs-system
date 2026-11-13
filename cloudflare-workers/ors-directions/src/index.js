/**
 * ATMOS TRS — OpenRouteService directions proxy.
 *
 * Flutter calls this Worker only. The ORS API key stays in a Worker secret
 * (`ORS_API_KEY`) and is never shipped to the browser.
 *
 * POST /directions
 * Body: { "coordinates": [[lng, lat], [lng, lat], ...] }
 * Response: { points: [{lat,lng}], distanceMeters, durationSeconds, provider }
 */

const DEFAULT_UPSTREAM =
  'https://api.heigit.org/openrouteservice/v2/directions/driving-car/geojson';

const ALLOWED_ORIGINS = new Set([
  'https://atmos-trs-system.web.app',
  'https://atmos-trs-system.firebaseapp.com',
  'http://localhost',
  'http://127.0.0.1',
]);

function corsHeaders(request) {
  const origin = request.headers.get('Origin') || '';
  let allow = 'https://atmos-trs-system.web.app';
  if (ALLOWED_ORIGINS.has(origin)) {
    allow = origin;
  } else if (
    origin.startsWith('http://localhost:') ||
    origin.startsWith('http://127.0.0.1:')
  ) {
    allow = origin;
  }
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

function json(body, status, request) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      ...corsHeaders(request),
    },
  });
}

function parseCoordinates(body) {
  const raw = body && body.coordinates;
  if (!Array.isArray(raw) || raw.length < 2) return null;
  const out = [];
  for (const pair of raw) {
    if (!Array.isArray(pair) || pair.length < 2) return null;
    const lng = Number(pair[0]);
    const lat = Number(pair[1]);
    if (!Number.isFinite(lng) || !Number.isFinite(lat)) return null;
    if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
    out.push([lng, lat]);
  }
  return out.length >= 2 ? out : null;
}

function lineStringToPoints(geometry) {
  if (!geometry || geometry.type !== 'LineString') return [];
  const coords = geometry.coordinates;
  if (!Array.isArray(coords)) return [];
  const points = [];
  for (const pair of coords) {
    if (!Array.isArray(pair) || pair.length < 2) continue;
    const lng = Number(pair[0]);
    const lat = Number(pair[1]);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    points.push({ lat, lng });
  }
  return points;
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(request) });
    }

    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';
    if (path !== '/directions' && path !== '') {
      return json(
        { error: 'NOT_FOUND', errorMessage: 'Use POST /directions' },
        404,
        request,
      );
    }

    if (request.method !== 'POST') {
      return json(
        { error: 'METHOD_NOT_ALLOWED', errorMessage: 'POST only' },
        405,
        request,
      );
    }

    const apiKey = (env.ORS_API_KEY || '').trim();
    if (!apiKey) {
      console.error('[ORS proxy] ORS_API_KEY secret is missing');
      return json(
        {
          error: 'MISCONFIGURED',
          errorMessage: 'ORS_API_KEY is not configured on the Worker',
        },
        500,
        request,
      );
    }

    let body;
    try {
      body = await request.json();
    } catch (_) {
      return json(
        { error: 'INVALID_JSON', errorMessage: 'Body must be JSON' },
        400,
        request,
      );
    }

    const coordinates = parseCoordinates(body);
    if (!coordinates) {
      return json(
        {
          error: 'INVALID_COORDINATES',
          errorMessage: 'Need coordinates: [[lng,lat], [lng,lat], ...]',
        },
        400,
        request,
      );
    }

    // ORS free tier typically allows limited waypoints per request.
    if (coordinates.length > 50) {
      return json(
        {
          error: 'TOO_MANY_WAYPOINTS',
          errorMessage: 'Max 50 coordinates per request',
        },
        400,
        request,
      );
    }

    const upstream =
      (env.ORS_UPSTREAM || '').trim() || DEFAULT_UPSTREAM;

    let orsRes;
    try {
      orsRes = await fetch(upstream, {
        method: 'POST',
        headers: {
          Authorization: apiKey,
          'Content-Type': 'application/json',
          Accept: 'application/json, application/geo+json',
        },
        body: JSON.stringify({ coordinates }),
      });
    } catch (e) {
      console.error('[ORS proxy] upstream fetch failed', String(e));
      return json(
        {
          error: 'UPSTREAM_ERROR',
          errorMessage: e && e.message ? e.message : String(e),
        },
        502,
        request,
      );
    }

    const text = await orsRes.text();
    let orsJson = null;
    try {
      orsJson = text ? JSON.parse(text) : null;
    } catch (_) {
      orsJson = null;
    }

    console.log(
      `[ORS proxy] status=${orsRes.status} coords=${coordinates.length} bodyBytes=${text.length}`,
    );

    if (!orsRes.ok) {
      const msg =
        (orsJson && (orsJson.error || orsJson.message)) ||
        text.slice(0, 240) ||
        `HTTP ${orsRes.status}`;
      return json(
        {
          error: `ORS_${orsRes.status}`,
          errorMessage: typeof msg === 'string' ? msg : JSON.stringify(msg),
          provider: 'openrouteservice',
          httpStatus: orsRes.status,
        },
        200,
        request,
      );
    }

    const feature =
      orsJson &&
      Array.isArray(orsJson.features) &&
      orsJson.features.length > 0
        ? orsJson.features[0]
        : null;
    const points = lineStringToPoints(feature && feature.geometry);
    if (points.length < 2) {
      return json(
        {
          error: 'NO_POLYLINE',
          errorMessage: 'Upstream returned no usable LineString',
          provider: 'openrouteservice',
          httpStatus: orsRes.status,
          pointCount: points.length,
        },
        200,
        request,
      );
    }

    const summary =
      (feature && feature.properties && feature.properties.summary) ||
      (orsJson &&
        orsJson.features &&
        orsJson.features[0] &&
        orsJson.features[0].properties &&
        orsJson.features[0].properties.segments &&
        orsJson.features[0].properties.segments[0]) ||
      {};

    const distanceMeters =
      typeof summary.distance === 'number' ? summary.distance : null;
    const durationSeconds =
      typeof summary.duration === 'number' ? summary.duration : null;

    return json(
      {
        provider: 'openrouteservice',
        httpStatus: orsRes.status,
        pointCount: points.length,
        points,
        distanceMeters,
        durationSeconds,
      },
      200,
      request,
    );
  },
};
