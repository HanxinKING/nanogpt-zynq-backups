@echo off
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
python -u %*
exit /b %ERRORLEVEL%
