@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-notify.ps1" %*
exit /b %ERRORLEVEL%
