@echo off
cd /d "%~dp0"
python -m pip install -q python-docx
python tools\docx_to_json.py %*
echo.
echo Now double-click setup_and_run.bat to see it in the app.
pause
