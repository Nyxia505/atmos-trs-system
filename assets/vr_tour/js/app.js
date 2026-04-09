/**
 * Marzipano 360 VR Tour – viewer, hotspots, sidebar, controls.
 * Depends: Marzipano, data.js (VR_TOUR_DATA).
 */
(function () {
  'use strict';

  var viewer = null;
  var sceneMap = {};  // sceneId -> Marzipano scene
  var currentSpot = null;
  var currentSceneId = null;
  var spotIdFromUrl = null;

  var el = {
    pano: null,
    sidebar: null,
    sidebarToggle: null,
    sceneList: null,
    titleBar: null,
    titleText: null,
    zoomIn: null,
    zoomOut: null,
    infoPopup: null,
    infoTitle: null,
    infoDesc: null,
    infoClose: null
  };

  function byId(id) { return document.getElementById(id); }

  function initElements() {
    el.pano = byId('pano');
    el.sidebar = byId('sidebar');
    el.sidebarToggle = byId('sidebar-toggle');
    el.sceneList = byId('scene-list');
    el.titleBar = byId('title-bar');
    el.titleText = byId('title-text');
    el.zoomIn = byId('zoom-in');
    el.zoomOut = byId('zoom-out');
    el.infoPopup = byId('info-popup');
    el.infoTitle = byId('info-title');
    el.infoDesc = byId('info-desc');
    el.infoClose = byId('info-close');
  }

  function parseQuery() {
    var params = {};
    var q = window.location.search.substring(1);
    if (!q) return params;
    q.split('&').forEach(function (part) {
      var kv = part.split('=');
      if (kv.length === 2) params[decodeURIComponent(kv[0])] = decodeURIComponent(kv[1]);
    });
    return params;
  }

  function initViewer() {
    var opts = {
      controls: { mouseViewMode: 'drag' },
      stage: { preserveDrawingBuffer: true }
    };
    viewer = new Marzipano.Viewer(el.pano, opts);
  }

  function createSceneFromData(spot, sceneData) {
    var levels = [{ width: 4096 }];
    var geometry = new Marzipano.EquirectGeometry(levels);
    var source = Marzipano.ImageUrlSource.fromString(sceneData.image);
    var initialView = sceneData.initialView || { yaw: 0, pitch: 0, fov: Math.PI / 2 };
    var limiter = Marzipano.RectilinearView.limit.traditional(4096, 120 * Math.PI / 180);
    var view = new Marzipano.RectilinearView(
      {
        yaw: initialView.yaw,
        pitch: initialView.pitch,
        fov: initialView.fov
      },
      limiter
    );
    var scene = viewer.createScene({
      source: source,
      geometry: geometry,
      view: view
    });
    return scene;
  }

  function createHotspotElement(hotspotData, onNav, onInfo) {
    var wrap = document.createElement('div');
    wrap.className = 'hotspot-wrap';

    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'hotspot-btn ' + (hotspotData.type === 'nav' ? 'hotspot-nav' : 'hotspot-info');
    btn.setAttribute('aria-label', hotspotData.label || hotspotData.title || 'Hotspot');

    if (hotspotData.type === 'nav') {
      btn.innerHTML = '<span class="hotspot-icon">→</span><span class="hotspot-label">' + (hotspotData.label || 'Go') + '</span>';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        if (onNav && hotspotData.targetSceneId) onNav(hotspotData.targetSceneId);
      });
    } else {
      btn.innerHTML = '<span class="hotspot-icon">ⓘ</span>';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        if (onInfo) onInfo(hotspotData);
      });
    }

    wrap.appendChild(btn);
    return wrap;
  }

  function addHotspotsToScene(marzipanoScene, sceneData, onNav, onInfo) {
    var container = marzipanoScene.hotspotContainer();
    (sceneData.hotspots || []).forEach(function (h) {
      var position = { yaw: h.yaw, pitch: h.pitch };
      var element = createHotspotElement(h, onNav, onInfo);
      container.createHotspot(element, position);
    });
  }

  function buildScenes(spot) {
    sceneMap = {};
    (spot.scenes || []).forEach(function (sceneData) {
      var scene = createSceneFromData(spot, sceneData);
      sceneMap[sceneData.id] = { scene: scene, data: sceneData };
      addHotspotsToScene(
        scene,
        sceneData,
        function (targetSceneId) { switchToScene(targetSceneId); },
        function (infoData) { openInfoPopup(infoData.title, infoData.description); }
      );
    });
  }

  function switchToScene(sceneId) {
    var entry = sceneMap[sceneId];
    if (!entry) return;
    currentSceneId = sceneId;
    entry.scene.switchTo({ transitionDuration: 800 });
    updateTitleBar(entry.data.name);
    updateSceneListSelection();
    closeInfoPopup();
  }

  function updateTitleBar(name) {
    if (el.titleText) el.titleText.textContent = name || '';
  }

  function updateSceneListSelection() {
    if (!el.sceneList) return;
    var items = el.sceneList.querySelectorAll('[data-scene-id]');
    items.forEach(function (item) {
      item.classList.toggle('active', item.getAttribute('data-scene-id') === currentSceneId);
    });
  }

  function openInfoPopup(title, description) {
    if (el.infoTitle) el.infoTitle.textContent = title || '';
    if (el.infoDesc) el.infoDesc.textContent = description || '';
    if (el.infoPopup) el.infoPopup.classList.add('open');
  }

  function closeInfoPopup() {
    if (el.infoPopup) el.infoPopup.classList.remove('open');
  }

  function renderSidebar(spot) {
    if (!el.sceneList) return;
    el.sceneList.innerHTML = '';
    (spot.scenes || []).forEach(function (s) {
      var li = document.createElement('li');
      li.setAttribute('data-scene-id', s.id);
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'scene-list-btn';
      btn.textContent = s.name;
      btn.addEventListener('click', function () { switchToScene(s.id); });
      li.appendChild(btn);
      el.sceneList.appendChild(li);
    });
    updateSceneListSelection();
  }

  function toggleSidebar() {
    if (el.sidebar) el.sidebar.classList.toggle('collapsed');
    var app = document.getElementById('app');
    if (app) app.classList.toggle('sidebar-collapsed', el.sidebar && el.sidebar.classList.contains('collapsed'));
  }

  function zoom(amount) {
    var entry = currentSceneId && sceneMap[currentSceneId];
    if (!entry) return;
    var view = entry.scene.view();
    var fov = view.fov();
    var newFov = Math.max(0.1, Math.min(Math.PI / 2, fov + amount));
    view.setFov(newFov);
  }

  function initControls() {
    if (el.zoomIn) el.zoomIn.addEventListener('click', function () { zoom(-0.08); });
    if (el.zoomOut) el.zoomOut.addEventListener('click', function () { zoom(0.08); });
    if (el.sidebarToggle) el.sidebarToggle.addEventListener('click', toggleSidebar);
    if (el.infoClose) el.infoClose.addEventListener('click', closeInfoPopup);
    if (el.infoPopup) {
      el.infoPopup.addEventListener('click', function (e) {
        if (e.target === el.infoPopup) closeInfoPopup();
      });
    }
  }

  function startTour() {
    var data = window.VR_TOUR_DATA;
    if (!data) return;

    var spotId = spotIdFromUrl || data.getDefaultSpotId();
    var spot = data.getTourSpot(spotId);
    if (!spot || !spot.scenes || !spot.scenes.length) return;

    currentSpot = spot;
    buildScenes(spot);

    var initialSceneId = data.getInitialSceneId(spot);
    if (initialSceneId) {
      currentSceneId = initialSceneId;
      var entry = sceneMap[initialSceneId];
      if (entry) {
        entry.scene.switchTo({ transitionDuration: 0 });
        updateTitleBar(entry.data.name);
      }
    }
    renderSidebar(spot);
    updateSceneListSelection();
  }

  function init() {
    initElements();
    var q = parseQuery();
    spotIdFromUrl = q.spot || q.spotId || null;

    initViewer();
    initControls();
    startTour();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
