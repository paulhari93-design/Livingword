@echo off
title LivingWord - keep PC awake
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\keep_awake.ps1" -Minutes 30
pause
