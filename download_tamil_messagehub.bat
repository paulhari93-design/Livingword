@echo off
title LivingWord - download Tamil messages from MessageHub
cd /d "%~dp0"
echo This downloads MessageHub's Tamil messages (text only) into:
echo   %USERPROFILE%\OneDrive\Desktop\APP_Books\Tamil_MessageHub
echo Your own Tamil Word files are not touched; in the app your translation is always used first.
echo Messages already downloaded are skipped. You can close this window and run it again later.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\download_all_messagehub.ps1" -Audio no -Lang ta
echo.
pause
