@echo off
setlocal
cd /d "%~dp0"

rem Auto-detect WLAN IPv4 address
set "LANIP="
for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq 'WLAN' -and $_.IPAddress -notlike '169.254*' } | Select-Object -First 1 -ExpandProperty IPAddress"') do set "LANIP=%%i"

if "%LANIP%"=="" (
  echo [ERROR] Could not detect WLAN IPv4. Check: netcmd ipconfig
  pause
  exit /b 1
)

echo ============================================================
echo  LAN IP detected: %LANIP%
echo  You open:          http://localhost:7357/
echo  Friends open:      http://%LANIP%:7357/
echo  (same Wi-Fi / hotspot only)
echo ============================================================
echo.

flutter run -d web-server --web-hostname 0.0.0.0 --web-port 7357 --dart-define=GOOGLE_WEB_CLIENT_ID=519145158335-uhre1sspgrplsn8louav88ad022ijopa.apps.googleusercontent.com --dart-define=AUTH_API_BASE_URL=http://%LANIP%:3002 --dart-define=FAMILY_API_BASE_URL=http://%LANIP%:3003 --dart-define=CHAT_API_BASE_URL=http://%LANIP%:3004
pause
