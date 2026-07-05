@echo off
echo === JanMat Citizen App — Run Script ===
echo.

REM Use embedded Flutter SDK
set FLUTTER=%~dp0..\flutter\bin\flutter.bat

REM 1. Get packages
echo [1/3] Getting packages...
%FLUTTER% pub get

REM 2. Check devices
echo.
echo [2/3] Available devices:
%FLUTTER% devices

REM 3. Run
echo.
echo [3/3] Launching app...
%FLUTTER% run --debug
