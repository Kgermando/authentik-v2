@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\build_msix.ps1"
if errorlevel 1 pause
