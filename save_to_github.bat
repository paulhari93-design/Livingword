@echo off
title LivingWord - save to GitHub
cd /d "%~dp0"

where git >nul 2>nul
if errorlevel 1 (
  echo Git was not found. Install Git from git-scm.com, then try again.
  pause
  exit /b
)

rem ---- One-time: your name and email for the history ----
git config --global user.name >nul 2>nul
if errorlevel 1 goto askname
goto checkemail
:askname
set /p GNAME=Your name (shown in the change history): 
git config --global user.name "%GNAME%"
:checkemail
git config --global user.email >nul 2>nul
if errorlevel 1 goto askemail
goto checkrepo
:askemail
set /p GEMAIL=Your GitHub email: 
git config --global user.email "%GEMAIL%"

rem ---- One-time: connect this folder to your GitHub repository ----
:checkrepo
if not exist .git git init -b main >nul
git remote get-url origin >nul 2>nul
if not errorlevel 1 goto save
echo.
echo First time only: paste the link of your empty GitHub repository
echo (looks like https://github.com/yourname/livingword.git)
set /p REPO=Link: 
git remote add origin %REPO%

rem ---- Every time: save and upload ----
:save
echo.
set MSG=
set /p MSG=What did you change? (press Enter to skip): 
if "%MSG%"=="" set MSG=Update %date% %time%
git add -A
git commit -m "%MSG%" >nul
echo.
echo Uploading to GitHub (a browser sign-in may open the first time)...
git push -u origin main
if errorlevel 1 (
  echo.
  echo Upload failed. Send a screenshot of this window to Claude.
) else (
  echo.
  echo Done. Your work is saved on GitHub.
)
pause
