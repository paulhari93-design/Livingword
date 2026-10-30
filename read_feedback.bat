@echo off
title LivingWord - feedback from the app
cd /d "%~dp0"
set KEY=%USERPROFILE%\Documents\livingword_keys\service-account.json
python -m pip install -q firebase-admin
if /i "%1"=="all" (
  python tools\feedback.py --key "%KEY%" --all
) else (
  python tools\feedback.py --key "%KEY%"
)
pause
