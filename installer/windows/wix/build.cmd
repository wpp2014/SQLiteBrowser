@echo off
setlocal EnableExtensions

for %%I in ("%~dp0..\..\..") do set "SQLITEBROWSER_ROOT=%%~fI"

where cmake.exe >nul 2>nul
if errorlevel 1 (
    echo ERROR: cmake.exe was not found in PATH.
    exit /b 1
)

if not exist "%SQLITEBROWSER_ROOT%\CMakePresets.json" (
    echo ERROR: CMakePresets.json was not found.
    echo Copy CMakePresets.template.json to CMakePresets.json and configure Qt first.
    exit /b 1
)

pushd "%SQLITEBROWSER_ROOT%" || exit /b 1
cmake --workflow --preset msi-release
set "SQLITEBROWSER_RESULT=%ERRORLEVEL%"
popd

if not "%SQLITEBROWSER_RESULT%"=="0" (
    echo ERROR: SQLiteBrowser MSI workflow failed.
    exit /b %SQLITEBROWSER_RESULT%
)

echo SQLiteBrowser MSI workflow completed successfully.
exit /b 0
