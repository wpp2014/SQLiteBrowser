@echo off
setlocal

pushd "%~dp0\..\..\.." >nul 2>&1
if errorlevel 1 (
  echo ERROR: Cannot enter the repository root.
  exit /b 1
)

where cmake.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: cmake.exe was not found in PATH.
  popd
  exit /b 1
)

cmake --workflow --preset portable-sfx-release
set "result=%ERRORLEVEL%"
popd
exit /b %result%
