@echo off
title LivingWord - take out messages that are not in your folders
cd /d "%~dp0"
echo This takes OUT of the app every message that is no longer in your APP_Books folders.
echo (Your files are not touched. Readers' highlights stay on their phones.)
echo.
call "%~dp0publish_books.bat" --dry-run --prune
echo.
set /p OK=The list above will be REMOVED. Type YES to continue: 
if /i not "%OK%"=="YES" exit /b
call "%~dp0publish_books.bat" --prune
