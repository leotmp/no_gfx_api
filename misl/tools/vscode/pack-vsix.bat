@echo off
setlocal
set "STAGE=%~1"
set "OUT=%~2"
if "%STAGE%"=="" exit /b 1
if "%OUT%"=="" exit /b 1
if exist "%OUT%" del /f /q "%OUT%"
set "ZIP=%OUT%.zip"
if exist "%ZIP%" del /f /q "%ZIP%"
tar.exe -a -cf "%ZIP%" -C "%STAGE%" extension extension.vsixmanifest "[Content_Types].xml"
if errorlevel 1 exit /b 1
move /y "%ZIP%" "%OUT%" >nul
if not exist "%OUT%" exit /b 1
