@echo off
title LivingWord - publish books
cd /d "%~dp0"
set BOOKS=%USERPROFILE%\OneDrive\Desktop\APP_Books
set KEY=%USERPROFILE%\Documents\livingword_keys\service-account.json

echo Publishing books from:
echo   %BOOKS%
echo.
python -m pip install -q python-docx firebase-admin pypdfium2 pypdf fonttools
python tools\publish_books.py --books "%BOOKS%" --key "%KEY%" %*
echo.
pause
