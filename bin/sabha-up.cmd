@echo off
rem Same as sabha-up.ps1, for cmd or a double-click: sabha-up.cmd [Name]
powershell -NoLogo -ExecutionPolicy Bypass -File "%~dp0sabha-up.ps1" %*
