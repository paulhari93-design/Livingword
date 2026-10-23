@echo off
rem Re-uploads EVERY book in APP_Books (silently, no notification).
rem Use this if the app seems to show an old version of the books.
call "%~dp0publish_books.bat" --force
