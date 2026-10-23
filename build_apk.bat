@echo off
title LivingWord - build APK
cd /d "%~dp0"

echo Preparing Firebase settings...
python tools\make_firebase_options.py "%USERPROFILE%\Documents\livingword_keys\google-services.json"
echo.
echo Building the APK (takes a few minutes)...
call flutter pub get
call dart run flutter_launcher_icons
call flutter build apk --release --split-per-abi
if errorlevel 1 (
  echo.
  echo Build failed. Send a screenshot of this window to Claude.
  pause
  exit /b
)

copy /y "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "LivingWord.apk" >nul
copy /y "build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk" "LivingWord-old-phones.apk" >nul
echo.
echo Done! LivingWord.apk is in this folder. Send it to your phone and tap it to install.
echo (LivingWord-old-phones.apk is only for very old phones that cannot install the normal one.)
explorer /select,"%~dp0LivingWord.apk"
pause
