@echo off
rem Starts OptiWin. It asks for administrator rights itself.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OptiWin.ps1"
