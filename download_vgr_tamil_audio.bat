@echo off
title LivingWord - download VGR Tamil audio
echo Downloads the Tamil sermon AUDIO from branham.org into Documents\VGR\Audio_Tamil.
echo This is large and takes hours. Files already there are skipped; you can stop and run it again.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\download_vgr.ps1" -Lang TAM -What audio %*
pause
