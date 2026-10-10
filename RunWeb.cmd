@echo off
cd /d "%~dp0"
flutter run -d chrome --web-hostname localhost --web-port 7357 --dart-define=GOOGLE_WEB_CLIENT_ID=519145158335-uhre1sspgrplsn8louav88ad022ijopa.apps.googleusercontent.com --dart-define=AUTH_API_BASE_URL=http://localhost:3002 --dart-define=FAMILY_API_BASE_URL=http://localhost:3003 --dart-define=CHAT_API_BASE_URL=http://localhost:3004
pause
