/**
 * VR Tour data – scalable by municipality and tourist spot.
 * Add more spots by extending TOUR_SPOTS and giving each spot a unique id and scenes array.
 *
 * Scene positions: yaw and pitch in radians (0 = center, positive yaw = right, positive pitch = down).
 * Hotspot types: 'nav' = switch scene, 'info' = show popup.
 */

(function (global) {
  'use strict';

  // Oroquieta City Plaza: single 360° image (relative to vr_tour/index.html -> assets/images)
  var OROQUIETA_PLAZA_IMAGE = '../images/oroquieta%20City%20plaza.jpeg';
  // Fallback if local image fails to load (e.g. when testing in browser without Flutter assets)
  var DEMO_IMAGE = 'https://cdn.pannellum.org/2.5.6/cerro-toco-0.jpg';
  var IMAGE_BASE = '';

  /**
   * All tour spots keyed by spot id. Each spot has:
   * - id: string
   * - name: string (tourist spot name)
   * - municipality: string
   * - scenes: array of scene objects
   */
  var TOUR_SPOTS = {
    'oroquieta-city-plaza': {
      id: 'oroquieta-city-plaza',
      name: 'Oroquieta City Plaza',
      municipality: 'Oroquieta City',
      scenes: [
        {
          id: 'plaza-entrance',
          name: 'City Plaza Entrance',
          image: OROQUIETA_PLAZA_IMAGE,
          initialView: { yaw: 0, pitch: 0, fov: Math.PI / 2 },
          hotspots: [
            { type: 'nav', targetSceneId: 'fountain-area', yaw: 0.4, pitch: 0.1, label: 'To Fountain' },
            { type: 'info', yaw: -0.3, pitch: 0.15, title: 'Main Entrance', description: 'Welcome to Oroquieta City Plaza. This is the main entrance from the city center, leading to the fountain and central areas.' }
          ]
        },
        {
          id: 'fountain-area',
          name: 'Fountain Area',
          image: OROQUIETA_PLAZA_IMAGE,
          initialView: { yaw: 0, pitch: 0, fov: Math.PI / 2 },
          hotspots: [
            { type: 'nav', targetSceneId: 'plaza-entrance', yaw: -0.5, pitch: 0, label: 'To Entrance' },
            { type: 'nav', targetSceneId: 'plaza-center', yaw: 0.3, pitch: 0.05, label: 'To Center' },
            { type: 'nav', targetSceneId: 'stage-area', yaw: 0.6, pitch: 0, label: 'To Stage' },
            { type: 'info', yaw: 0.1, pitch: -0.2, title: 'Central Fountain', description: 'The plaza fountain is a popular landmark and gathering point. It is lit at night during special events.' }
          ]
        },
        {
          id: 'plaza-center',
          name: 'Plaza Center',
          image: OROQUIETA_PLAZA_IMAGE,
          initialView: { yaw: 0, pitch: 0, fov: Math.PI / 2 },
          hotspots: [
            { type: 'nav', targetSceneId: 'fountain-area', yaw: -0.4, pitch: 0, label: 'To Fountain' },
            { type: 'nav', targetSceneId: 'stage-area', yaw: 0.5, pitch: 0.05, label: 'To Stage' },
            { type: 'nav', targetSceneId: 'plaza-entrance', yaw: Math.PI, pitch: 0, label: 'To Entrance' },
            { type: 'info', yaw: 0, pitch: 0.1, title: 'Plaza Center', description: 'The heart of the plaza. Open space used for events, morning exercise, and community gatherings.' }
          ]
        },
        {
          id: 'stage-area',
          name: 'Stage Area',
          image: OROQUIETA_PLAZA_IMAGE,
          initialView: { yaw: 0, pitch: 0, fov: Math.PI / 2 },
          hotspots: [
            { type: 'nav', targetSceneId: 'plaza-center', yaw: -0.5, pitch: 0, label: 'To Center' },
            { type: 'nav', targetSceneId: 'fountain-area', yaw: -0.8, pitch: 0, label: 'To Fountain' },
            { type: 'info', yaw: 0.2, pitch: -0.1, title: 'Plaza Stage', description: 'The stage hosts cultural shows, holiday programs, and official ceremonies. A focal point during festivals.' }
          ]
        }
      ]
    }
  };

  /**
   * Get tour data for a spot id. Returns null if not found.
   */
  function getTourSpot(spotId) {
    return TOUR_SPOTS[spotId] || null;
  }

  /**
   * Get default spot id (first key). Used when no spot is specified in URL.
   */
  function getDefaultSpotId() {
    var keys = Object.keys(TOUR_SPOTS);
    return keys.length ? keys[0] : null;
  }

  /**
   * Get initial scene id for a spot (first scene in list).
   */
  function getInitialSceneId(spot) {
    return spot && spot.scenes && spot.scenes.length
      ? spot.scenes[0].id
      : null;
  }

  global.VR_TOUR_DATA = {
    TOUR_SPOTS: TOUR_SPOTS,
    getTourSpot: getTourSpot,
    getDefaultSpotId: getDefaultSpotId,
    getInitialSceneId: getInitialSceneId,
    IMAGE_BASE: IMAGE_BASE
  };
})(typeof window !== 'undefined' ? window : this);
