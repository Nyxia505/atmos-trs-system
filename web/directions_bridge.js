// Google Maps JS DirectionsService (no CORS). Used by Flutter web Trip Route.
(function () {
  function parseWaypoint(p) {
    return { lat: Number(p.lat), lng: Number(p.lng) };
  }

  function decodePolyline(encoded) {
    const points = [];
    let index = 0;
    let lat = 0;
    let lng = 0;
    while (index < encoded.length) {
      let b;
      let shift = 0;
      let result = 0;
      do {
        b = encoded.charCodeAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      const dlat = (result & 1) !== 0 ? ~(result >> 1) : result >> 1;
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.charCodeAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      const dlng = (result & 1) !== 0 ? ~(result >> 1) : result >> 1;
      lng += dlng;
      points.push({ lat: lat / 1e5, lng: lng / 1e5 });
    }
    return points;
  }

  function mergePoints(target, decoded) {
    for (let i = 0; i < decoded.length; i++) {
      const p = decoded[i];
      const last = target[target.length - 1];
      if (last && last.lat === p.lat && last.lng === p.lng) continue;
      target.push(p);
    }
  }

  function pointsFromRoute(route) {
    const points = [];
    const legs = route && route.legs;
    if (!legs || !legs.length) {
      const enc =
        route && route.overview_polyline && route.overview_polyline.points;
      return enc ? decodePolyline(enc) : [];
    }
    for (const leg of legs) {
      const steps = leg.steps;
      if (!steps) continue;
      for (const step of steps) {
        const enc = step.polyline && step.polyline.points;
        if (enc) mergePoints(points, decodePolyline(enc));
      }
    }
    if (points.length < 2) {
      const enc =
        route && route.overview_polyline && route.overview_polyline.points;
      if (enc) return decodePolyline(enc);
    }
    return points;
  }

  function routeRequest(service, origin, destination, middle) {
    return new Promise((resolve) => {
      const request = {
        origin: parseWaypoint(origin),
        destination: parseWaypoint(destination),
        travelMode: google.maps.TravelMode.DRIVING,
      };
      if (middle && middle.length) {
        request.waypoints = middle.map((w) => ({
          location: parseWaypoint(w),
          stopover: true,
        }));
      }
      service.route(request, (result, status) => {
        if (status !== google.maps.DirectionsStatus.OK) {
          resolve({ errorStatus: status });
          return;
        }
        const route = result.routes && result.routes[0];
        const points = pointsFromRoute(route);
        if (points.length < 2) {
          resolve({ errorStatus: "NO_POLYLINE" });
          return;
        }
        resolve({ points: points });
      });
    });
  }

  async function routeLegByLeg(service, waypoints) {
    const merged = [];
    for (let i = 0; i < waypoints.length - 1; i++) {
      const leg = await routeRequest(
        service,
        waypoints[i],
        waypoints[i + 1],
        []
      );
      if (!leg.points || leg.points.length < 2) return leg;
      if (merged.length === 0) {
        merged.push(...leg.points);
      } else {
        merged.push(...leg.points.slice(1));
      }
    }
    return { points: merged };
  }

  function waitForGoogleMaps(maxMs) {
    return new Promise((resolve) => {
      const start = Date.now();
      (function tick() {
        if (
          window.google &&
          google.maps &&
          google.maps.DirectionsService &&
          google.maps.TravelMode
        ) {
          resolve(true);
          return;
        }
        if (Date.now() - start >= maxMs) {
          resolve(false);
          return;
        }
        setTimeout(tick, 50);
      })();
    });
  }

  window.tripPlanGetDirectionsRoute = function (waypointsJson) {
    return new Promise((resolve) => {
      (async () => {
      try {
        const waypoints = JSON.parse(waypointsJson);
        if (!waypoints || waypoints.length < 2) {
          resolve(JSON.stringify({ errorStatus: "TOO_FEW_POINTS" }));
          return;
        }
        const mapsReady = await waitForGoogleMaps(20000);
        if (!mapsReady) {
          resolve(JSON.stringify({ errorStatus: "NO_GOOGLE_MAPS" }));
          return;
        }
        const service = new google.maps.DirectionsService();
        routeRequest(
          service,
          waypoints[0],
          waypoints[waypoints.length - 1],
          waypoints.slice(1, waypoints.length - 1)
        )
          .then(async (result) => {
            if (result.points && result.points.length >= 2) {
              resolve(JSON.stringify(result));
              return;
            }
            const legs = await routeLegByLeg(service, waypoints);
            resolve(JSON.stringify(legs));
          })
          .catch((e) => {
            resolve(
              JSON.stringify({
                errorStatus: "ERROR",
                errorMessage: String(e),
              })
            );
          });
      } catch (e) {
        resolve(
          JSON.stringify({
            errorStatus: "ERROR",
            errorMessage: String(e),
          })
        );
      }
      })();
    });
  };
})();
