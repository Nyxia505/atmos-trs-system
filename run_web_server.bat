@echo off
setlocal
cd /d "%~dp0"

echo.
echo  ATMOS TRS - Web server (no Chrome debugger attach)
echo  ----------------------------------------
echo  After "lib\main.dart is being served at", open:
echo    http://127.0.0.1:7357
echo  in Chrome or Edge manually.
echo  If Firewall asks, click ALLOW.
echo  ----------------------------------------
echo.

flutter pub get
if errorlevel 1 exit /b 1

flutter run -d web-server --web-port=7357 --web-hostname=127.0.0.1 --no-wasm-dry-run

pause
