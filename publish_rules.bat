@echo off
title LivingWord - publish database rules
cd /d "%~dp0"
echo Publishes firestore.rules: who may read and write the app database.
echo Needed once for Feedback. Messages and the Bible stay readable for everyone.
echo.
call firebase login
call firebase deploy --only firestore:rules --project livingword-dc416
pause
