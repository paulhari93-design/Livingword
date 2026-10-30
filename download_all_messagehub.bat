@echo off
title LivingWord - download all English messages from MessageHub
cd /d "%~dp0"
echo This downloads ALL English messages (text only) from MessageHub into:
echo   %USERPROFILE%\OneDrive\Desktop\APP_Books\English
echo Messages already in that folder are skipped, never downloaded again.
echo You can close this window any time and run it again later to continue.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\download_all_messagehub.ps1" -Audio no
echo.
pause
