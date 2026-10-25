@echo off
title LivingWord - download English messages from MessageHub
cd /d "%~dp0"
echo Downloading the English version of each Tamil message in APP_Books...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\download_english.ps1"
echo.
echo Done. Tell Claude the download has finished.
pause
