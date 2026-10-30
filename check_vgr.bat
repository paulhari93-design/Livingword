@echo off
title LivingWord - check VGR pages
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\check_vgr.ps1"
pause
