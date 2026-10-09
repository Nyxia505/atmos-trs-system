# Web assets (optional for dev)

These files are used only for **web** so the logo and font load when the Flutter dev server does not serve the asset manifest (e.g. `flutter run -d chrome`).

- **Does not affect** Android, iOS, or a normal **release** web build (`flutter build web` + deploy). Those use `assets/` and `pubspec.yaml` as usual.
- **For web**: If `tripplan.png` and `fonts/` are present here, they are copied into `build/web/` on `flutter build web` and the app uses them. If missing, the app still works in release builds (asset bundle is used).

To add/update them once (e.g. after changing logo or font in `assets/`), run from project root:

```bat
prepare_web_assets.bat
```

Or copy manually: `assets/images/tripplan.png` → `web/tripplan.png`, and `assets/fonts/*.ttf` → `web/fonts/`. You can commit `web/tripplan.png` and `web/fonts/` so future builds and other devs don't need to run the script.
