@echo off
setlocal
cd /d "%~dp0"

echo Building web release (one time, ~90s)...
call flutter build web --no-wasm-dry-run
if errorlevel 1 exit /b 1

echo.
echo Serving at http://127.0.0.1:8080
echo Press Ctrl+C to stop.
echo.

cd build\web
python -m http.server 8080

pause
