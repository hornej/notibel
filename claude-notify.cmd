@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-notify.ps1"
exit /b %ERRORLEVEL%
