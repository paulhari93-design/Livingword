@echo off
title LivingWord - build APK
cd /d "%~dp0"

echo Converting Word files in the my_messages folder...
if exist "my_messages\*.docx" (
  python -m pip install -q python-docx
  for %%f in ("my_messages\*.docx") do python tools\docx_to_json.py "%%f"
)

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
