@echo off
title LivingWord - download VGR Tamil messages (text)
echo Downloads the Tamil sermons (PDF) from branham.org into APP_Books\Tamil_VGR.
echo Files already there are skipped.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\download_vgr.ps1" -Lang TAM -What text %*
pause
