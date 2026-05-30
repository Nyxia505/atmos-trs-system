@echo off
cd /d "%~dp0"
if not exist "web\tripplan.png" (
  echo Copying logo and font to web/...
  call prepare_web_assets.bat
)
if not exist "build\web\index.html" (
  echo Building web app first...
  call flutter build web --no-tree-shake-icons
  echo.
)
echo Serving at http://localhost:8080 - open in Chrome.
echo Close this window to stop.
cd build\web
python -m http.server 8080
pause
