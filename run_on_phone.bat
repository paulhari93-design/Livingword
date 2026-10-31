@echo off
title LivingWord - run on my phone (USB)
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter was not found. Install the Flutter SDK and add it to PATH, then try again.
  pause
  exit /b
)

set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
if not exist "%ADB%" set ADB=adb

echo Preparing Firebase settings...
python tools\make_firebase_options.py "%USERPROFILE%\Documents\livingword_keys\google-services.json"
call flutter pub get >nul

:look
echo.
echo Looking for your phone on the USB cable...
"%ADB%" kill-server >nul 2>nul
"%ADB%" start-server >nul 2>nul
set PHONE=
set WAITING=
for /f "skip=1 tokens=1,2" %%a in ('call "%ADB%" devices') do (
  echo %%a | findstr /b /c:"emulator-" >nul
  if errorlevel 1 (
    if "%%b"=="device" if not defined PHONE set PHONE=%%a
    if "%%b"=="unauthorized" set WAITING=1
  )
)

if defined PHONE goto found

echo.
if defined WAITING (
  echo Your phone is connected but has not allowed this PC yet.
  echo   Unlock the phone. A box "Allow USB debugging?" should be on the screen.
  echo   Tick "Always allow from this computer" and press Allow.
) else (
  echo No phone found. Please check:
  echo   1. The USB cable is plugged in and can carry data (some cables only charge^).
  echo   2. On the phone: Settings - Developer options - USB debugging is ON.
  echo   3. When you plug in, choose "File transfer" if the phone asks what the USB is for.
  echo   4. Unlock the phone and press Allow on "Allow USB debugging?".
)
echo.
echo Press any key to look again (or close this window).
pause >nul
goto look

:found
echo Found your phone: %PHONE%
echo.
echo Building and installing the app on your phone (the first time takes a few minutes)...
echo When it is running: press Shift+R here after Claude sends changes.
echo.
call flutter run -d %PHONE%
echo.
echo If you saw INSTALL_FAILED_UPDATE_INCOMPATIBLE above: the Play Store version of LivingWord
echo is on this phone. Uninstall it from the phone (your bookmarks and highlights on this phone
echo will be removed), then run this file again.
pause
