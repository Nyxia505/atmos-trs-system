@echo off
cd /d "%~dp0"
if not exist "web\tripplan.png" (
  echo Preparing web assets...
  if not exist "web\fonts" mkdir "web\fonts"
  copy /Y "assets\images\tripplan.png" "web\tripplan.png" >nul 2>&1
  copy /Y "assets\fonts\holiday-calling-non-commercial-use.noncommercialuse.ttf" "web\fonts\" >nul 2>&1
)
echo Building and running web...
flutter run -d chrome --web-renderer=html --release
pause
