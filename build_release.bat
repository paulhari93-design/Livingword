@echo off
title LivingWord - build for Google Play
cd /d "%~dp0"
set KEYDIR=%USERPROFILE%\Documents\livingword_keys
set KS=%KEYDIR%\upload-keystore.jks
set KSFWD=%KS:\=/%

if not exist "%KEYDIR%" mkdir "%KEYDIR%"

rem ---- One time: create your upload key ----
if exist "%KS%" goto havekey
set KEYTOOL=%ProgramFiles%\Android\Android Studio\jbr\bin\keytool.exe
if not exist "%KEYTOOL%" set KEYTOOL=keytool
for /f %%p in ('powershell -NoProfile -Command "[guid]::NewGuid().ToString('N')"') do set PW=%%p
echo Creating your upload key (one time only)...
"%KEYTOOL%" -genkeypair -keystore "%KS%" -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload -storepass %PW% -keypass %PW% -dname "CN=LivingWord, O=LivingWord, C=IN"
if errorlevel 1 (
  echo Could not create the key. Send a screenshot of this window to Claude.
  pause
  exit /b
)
(
  echo storeFile=%KSFWD%
  echo storePassword=%PW%
  echo keyAlias=upload
  echo keyPassword=%PW%
) > "%KEYDIR%\key.properties"
echo.
echo Your upload key is saved in %KEYDIR%
echo IMPORTANT: back up the whole livingword_keys folder (e.g. to Google Drive or a USB stick).
echo.
:havekey
copy /y "%KEYDIR%\key.properties" "android\key.properties" >nul

echo Preparing Firebase settings...
python tools\make_firebase_options.py "%KEYDIR%\google-services.json"

echo.
echo Building the Google Play file (takes a few minutes)...
call flutter pub get
call dart run flutter_launcher_icons
call flutter build appbundle --release
if errorlevel 1 (
  echo.
  echo Build failed. Send a screenshot of this window to Claude.
  pause
  exit /b
)
copy /y "build\app\outputs\bundle\release\app-release.aab" "LivingWord-release.aab" >nul
echo.
echo Done! Upload LivingWord-release.aab in the Google Play Console.
echo (For every new upload, first raise the number after + in pubspec.yaml "version:", e.g. 1.0.0+2)
explorer /select,"%~dp0LivingWord-release.aab"
pause
