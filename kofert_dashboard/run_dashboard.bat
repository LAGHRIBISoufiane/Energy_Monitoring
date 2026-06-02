@echo off
echo Closing existing Edge instances...
taskkill /F /IM msedge.exe /T >nul 2>&1
timeout /t 3 /nobreak >nul
echo Launching KOFERT Dashboard on Edge...
cd /d "%~dp0"
flutter run -d edge
