@echo off
title LivingWord - get VGR series lists
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\get_vgr_series.ps1"
pause
