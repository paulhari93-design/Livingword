@echo off
title LivingWord - setup and run
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo.
  echo Flutter was not found. Install the Flutter SDK and add it to PATH,
  echo then close this window and double-click this file again.
  pause
  exit /b
)

echo.
echo [1/4] Creating the Android project files...
call flutter create --platforms android --org com.livingword --project-name livingword .
if exist test\widget_test.dart del test\widget_test.dart

echo.
echo Converting Word files in the my_messages folder...
if exist "my_messages\*.docx" (
  python -m pip install -q python-docx
  for %%f in ("my_messages\*.docx") do python tools\docx_to_json.py "%%f"
) else (
  echo No Word files found in my_messages - showing the sample only.
)
echo.
echo [2/4] Downloading packages...
call flutter pub get
call dart run flutter_launcher_icons

echo.
echo [3/4] Starting the emulator...
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
if exist "%ADB%" (
  echo Resetting the connection to the emulator...
  "%ADB%" kill-server >nul 2>nul
  "%ADB%" start-server >nul 2>nul
  timeout /t 5 /nobreak >nul
)
flutter devices | findstr /c:"android-" >nul
if not errorlevel 1 (
  echo Emulator is already running.
  goto run
)
set EMU=
for /f "tokens=1" %%i in ('flutter emulators ^| findstr /c:"android"') do (
  if not defined EMU set EMU=%%i
)
if not defined EMU (
  echo No emulator found. Open Android Studio, Device Manager, click + and create a phone.
  echo Then double-click this file again.
  pause
  exit /b
)
call flutter emulators --launch %EMU%
echo Waiting for the emulator to start (up to 4 minutes)...
set /a TRIES=0
:waitloop
timeout /t 10 /nobreak >nul
flutter devices | findstr /c:"android-" >nul
if not errorlevel 1 goto booted
set /a TRIES+=1
if %TRIES% GEQ 24 (
  echo The emulator did not start. Start it from Android Studio - Device Manager - play button, then run this file again.
  pause
  exit /b
)
if %TRIES%==6 if exist "%ADB%" ("%ADB%" kill-server >nul 2>nul & "%ADB%" start-server >nul 2>nul)
echo   still starting...
goto waitloop
:booted
echo Emulator is ready. Giving it 20 more seconds to finish loading...
timeout /t 20 /nobreak >nul

:run
echo.
echo [4/4] Building and opening the app (first build takes a few minutes)...
call flutter run -d emulator
pause
