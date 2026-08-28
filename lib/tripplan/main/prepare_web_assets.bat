@echo off
cd /d "%~dp0"
echo Copying logo and font to web/ (used only for web; does not affect Android/iOS or release).
if not exist "web\fonts" mkdir "web\fonts"
copy /Y "assets\images\tripplan.png" "web\tripplan.png" >nul 2>&1
copy /Y "assets\fonts\holiday-calling-non-commercial-use.noncommercialuse.ttf" "web\fonts\" >nul 2>&1
echo Done. Optional: commit web\tripplan.png and web\fonts\ for future builds.
pause
