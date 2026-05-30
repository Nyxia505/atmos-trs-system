@echo off
setlocal
cd /d "%~dp0"

echo.
echo  ATMOS TRS - Web (Chrome)
echo  ----------------------------------------
echo  First run can take 2-3 minutes while compiling.
echo  If Windows Firewall appears, choose ALLOW for:
echo    - Dart / flutter / Private networks
echo  ----------------------------------------
echo.

flutter pub get
if errorlevel 1 exit /b 1

REM Avoid wasm dry-run delay; fixed port for firewall rules.
flutter run -d chrome --web-port=7357 --web-hostname=127.0.0.1 --no-wasm-dry-run

pause
