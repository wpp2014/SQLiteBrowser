@echo off
setlocal EnableExtensions

if /I "%~1"=="--help" goto :show_help
if /I "%~1"=="-h" goto :show_help
if /I "%~1"=="/?" goto :show_help

set "WINDOWS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%WINDOWS_POWERSHELL%" (
    echo ERROR: Windows PowerShell was not found at the required default path.
    echo Expected: %WINDOWS_POWERSHELL%
    exit /b 1
)

"%WINDOWS_POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass ^
    -File "%~dp0aggregate.ps1" %*
exit /b %ERRORLEVEL%

:show_help
echo Usage: third_party\aggregate.cmd ^<build^|check^|clean^> [all^|debug^|release]
echo.
echo   build  Validate private dependency stages and publish the public aggregate.
echo   check  Validate private stages and any existing public aggregate without changes.
echo   clean  Remove only files recorded in the public ownership manifest.
echo.
echo Defaults: build all
exit /b 0
