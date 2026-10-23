@echo off
title LivingWord - remove a book from the app
cd /d "%~dp0"
echo This takes a book OUT of the app (from Firebase). Your Word files are not touched.
echo.
set /p CODE=Type the code of the book to remove (for example 53-1216): 
if "%CODE%"=="" exit /b
call "%~dp0publish_books.bat" --remove %CODE%
