@echo off
REM Start Flash-Next llama-server. Extra args are passed through (e.g. -WebUi -NoAuth).
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*
if errorlevel 1 powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*
