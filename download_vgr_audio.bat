@echo off
title LivingWord - download VGR English audio
echo Downloads the English sermon AUDIO from branham.org into Documents\VGR\Audio_English.
echo WARNING: this is very large (tens of GB) and takes many hours. Files already there are skipped.
echo You can close this window any time and run it again later; it continues where it stopped.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\download_vgr.ps1" -What audio %*
pause
