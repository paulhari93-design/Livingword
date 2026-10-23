@echo off
title LivingWord - clean and rebuild
cd /d "%~dp0"
echo Cleaning old build files (this fixes most build errors)...
call flutter clean
echo.
echo Downloading packages again...
call flutter pub get
if errorlevel 1 (
  echo.
  echo Packages failed. Repairing the package cache, this can take a few minutes...
  call flutter pub cache repair
  call flutter pub get
)
echo.
echo Done cleaning. Now starting the app...
call "%~dp0setup_and_run.bat"
