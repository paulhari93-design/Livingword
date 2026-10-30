@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\check_messagehub.ps1"
echo.
echo Done. Tell Claude.
pause
