# 360° VR Tour (Marzipano)

Web-based 360° virtual tour for the tourism app. Used in-app via Flutter WebView or in a browser.

## Features

- **360° panoramic viewer** (Marzipano)
- **Multiple scenes** per tourist spot (e.g. Plaza Entrance, Fountain, Center, Stage)
- **Navigation hotspots** – click to switch to another scene
- **Info hotspots** – click to open a popup with title and description
- **Left sidebar** – collapsible scene list
- **Top title bar** – current scene name
- **Zoom in/out** and drag to look around
- **Orange & white** styling; mobile-friendly

## Project structure

```
assets/vr_tour/
├── index.html       # Entry page
├── css/
│   └── styles.css   # Layout, sidebar, popup, controls
├── js/
│   ├── data.js      # Tour data (spots, scenes, hotspots) – scalable
│   └── app.js       # Marzipano viewer, hotspots, UI logic
├── images/          # Optional: place scene panoramas here (see below)
└── README.md
```

## Data structure (scalable)

Tour data lives in `js/data.js`:

- **TOUR_SPOTS** – map of spot id → `{ id, name, municipality, scenes }`
- Each **scene**: `id`, `name`, `image` (URL or path), `initialView`, `hotspots`
- **Hotspots**: `type: 'nav' | 'info'`, `yaw`, `pitch`, and for nav `targetSceneId`/`label`, for info `title`/`description`

To add another municipality or tourist spot, add a new key to `TOUR_SPOTS` with its own `scenes` array. The HTML supports `?spot=spotId` to open a specific tour (when loaded via URL).

## Scene images

- **Demo**: If no local images are set, the tour uses a single demo equirectangular image so it runs without assets.
- **Production**: Set `IMAGE_BASE` in `data.js` (e.g. to your CDN or `''` for relative paths), then add under `images/` one equirectangular panorama per scene (e.g. `plaza_entrance.jpg`) and reference them in each scene’s `image` field. Or use the [Marzipano Tool](https://www.marzipano.net/tool) to generate multiresolution tiles and switch to cube geometry if needed.

## Opening the tour from Flutter

1. **In-app (Android/iOS)** – load the bundled tour in a WebView:

   ```dart
   import 'package:atmos_trs_system/screens/vr_webview_screen.dart';

   // Open the bundled Oroquieta City Plaza 360° tour
   openVrTour(
     context,
     useLocalTour: true,
     title: 'Oroquieta City Plaza',
   );
   ```

2. **External URL** (e.g. hosted tour):

   ```dart
   openVrTour(
     context,
     url: 'https://yoursite.com/vr/',
     title: 'VR Tour',
   );
   ```

Ensure `assets/vr_tour/` is listed in `pubspec.yaml` under `flutter.assets` so the WebView can load `assets/vr_tour/index.html` and its relative CSS/JS.

## Testing in a browser

Serve the `assets/vr_tour` folder (e.g. with a local HTTP server) and open `index.html`. Use `?spot=oroquieta-city-plaza` to select the tour. The Marzipano script is loaded from CDN.
