@echo off
title LivingWord - publish privacy policy
cd /d "%~dp0"

where npm >nul 2>nul
if errorlevel 1 (
  echo Node.js was not found. Install it from nodejs.org, then try again.
  pause
  exit /b
)

where firebase >nul 2>nul
if errorlevel 1 (
  echo Installing the Firebase tool - one time only...
  call npm install -g firebase-tools
)

echo.
echo Signing in to Firebase - a browser window may open the first time.
echo Use the same Google account as your Firebase project.
call firebase login

echo.
echo Reserving the web address livingword-tamil.web.app - one time only...
call firebase hosting:sites:create livingword-tamil --project livingword-dc416 >nul 2>nul

echo.
echo Publishing the privacy policy...
call firebase deploy --only hosting --project livingword-dc416
if errorlevel 1 (
  echo.
  echo Publishing failed. Send a screenshot of this window to Claude.
  pause
  exit /b
)
echo.
echo Done! Your privacy policy link:
echo    https://livingword-tamil.web.app/privacy.html
start "" https://livingword-tamil.web.app/privacy.html
pause
