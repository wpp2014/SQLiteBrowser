@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "PROJECT_ROOT=%%~fI"
for %%I in ("%SCRIPT_DIR%.") do set "ZLIB_CMAKE_DIR=%%~fI"

set "ZLIB_SRC=%SCRIPT_DIR%src"
set "ZLIB_BUILD_ROOT=%PROJECT_ROOT%\build\zlib"
set "EXPECTED_ZLIB_COMMIT=da607da739fa6047df13e66a2af6b8bec7c2a498"
set "EXPECTED_ZLIB_TAG=v1.3.2"
set "REQUIRED_WINDOWS_SDK=10.0.22621.0"
set "WINDOWS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

set "BUILD_CONFIG=all"
set "CLEAN_BUILD=0"
set "CHECK_ONLY=0"

:parse_arguments
if "%~1"=="" goto arguments_parsed

if /i "%~1"=="all" (
    set "BUILD_CONFIG=all"
) else if /i "%~1"=="debug" (
    set "BUILD_CONFIG=debug"
) else if /i "%~1"=="release" (
    set "BUILD_CONFIG=release"
) else if /i "%~1"=="clean" (
    set "CLEAN_BUILD=1"
) else if /i "%~1"=="check" (
    set "CHECK_ONLY=1"
) else if /i "%~1"=="--help" (
    goto show_help
) else if /i "%~1"=="-h" (
    goto show_help
) else if /i "%~1"=="/?" (
    goto show_help
) else (
    echo ERROR: Unknown argument "%~1".
    echo.
    goto show_help_error
)

shift
goto parse_arguments

:arguments_parsed
if "!CHECK_ONLY!"=="1" if "!CLEAN_BUILD!"=="1" (
    echo ERROR: check and clean cannot be used together.
    exit /b 1
)

set "LC_ALL=C"
set "LANG=C"
set "LANGUAGE="
set "VSCMD_SKIP_SENDTELEMETRY=1"

echo [zlib] Project root:  !PROJECT_ROOT!
echo [zlib] Source:        !ZLIB_SRC!
echo [zlib] Configuration: !BUILD_CONFIG!
if "!CLEAN_BUILD!"=="1" echo [zlib] Clean rebuild: yes
if "!CHECK_ONLY!"=="1" echo [zlib] Check only: yes
echo.

call :require_tool git.exe "Install Git and add git.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool cmake.exe "Install CMake 3.21 or newer and add cmake.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool ctest.exe "Install CMake with CTest and add ctest.exe to PATH."
if errorlevel 1 exit /b 1
if not exist "!WINDOWS_POWERSHELL!" (
    echo ERROR: Windows PowerShell was not found at the required default path.
    echo Expected: !WINDOWS_POWERSHELL!
    exit /b 1
)
call :require_tool certutil.exe "Windows certutil.exe is required to calculate artifact SHA-256 values."
if errorlevel 1 exit /b 1

call :check_cmake_version
if errorlevel 1 exit /b 1

if not exist "!ZLIB_SRC!\CMakeLists.txt" (
    if "!CHECK_ONLY!"=="1" (
        echo ERROR: The zlib submodule is not initialised: !ZLIB_SRC!
        echo Run: git submodule update --init --recursive
        exit /b 1
    )

    echo [zlib] Initialising the zlib submodule...
    git -C "!PROJECT_ROOT!" submodule update --init --recursive -- third_party/zlib/src
    if errorlevel 1 (
        echo ERROR: Failed to initialise the zlib submodule.
        exit /b 1
    )
)

if not exist "!ZLIB_SRC!\CMakeLists.txt" (
    echo ERROR: zlib CMakeLists.txt is missing after submodule initialisation.
    exit /b 1
)

set "ZLIB_COMMIT="
for /f "usebackq delims=" %%I in (`git -C "!ZLIB_SRC!" rev-parse HEAD 2^>nul`) do set "ZLIB_COMMIT=%%I"
if not defined ZLIB_COMMIT (
    echo ERROR: Unable to read the zlib submodule commit.
    exit /b 1
)
if /i not "!ZLIB_COMMIT!"=="!EXPECTED_ZLIB_COMMIT!" (
    echo ERROR: Unexpected zlib submodule commit.
    echo Expected: !EXPECTED_ZLIB_COMMIT! ^(!EXPECTED_ZLIB_TAG!^)
    echo Actual:   !ZLIB_COMMIT!
    echo Refusing to build an unverified zlib revision.
    exit /b 1
)

set "ZLIB_TAG="
for /f "usebackq delims=" %%I in (`git -C "!ZLIB_SRC!" describe --tags --exact-match 2^>nul`) do set "ZLIB_TAG=%%I"
if /i not "!ZLIB_TAG!"=="!EXPECTED_ZLIB_TAG!" (
    echo ERROR: The zlib submodule is not checked out at tag !EXPECTED_ZLIB_TAG!.
    echo Actual tag: !ZLIB_TAG!
    exit /b 1
)

set "ZLIB_DIRTY="
for /f "usebackq delims=" %%I in (`git -C "!ZLIB_SRC!" status --porcelain=v1 --untracked-files=all --ignore-submodules=all 2^>nul`) do set "ZLIB_DIRTY=1"
if defined ZLIB_DIRTY (
    echo ERROR: The zlib source submodule has local changes.
    echo Commit, stash, or remove those changes before building.
    git -C "!ZLIB_SRC!" status --short --ignore-submodules=all
    exit /b 1
)

call :find_visual_studio
if errorlevel 1 exit /b 1

echo [zlib] Visual Studio: !VS_EDITION! 2022
echo [zlib] Initialising MSVC x64 with Windows SDK !REQUIRED_WINDOWS_SDK!...
call "!VS_DEVCMD!" -no_logo -arch=x64 -host_arch=x64 -winsdk=!REQUIRED_WINDOWS_SDK!
if errorlevel 1 (
    echo ERROR: Visual Studio developer environment initialisation failed.
    exit /b 1
)

call :require_tool cl.exe "Install the Visual Studio 2022 Desktop development with C++ workload."
if errorlevel 1 exit /b 1
call :require_tool dumpbin.exe "Install the Visual Studio 2022 MSVC v143 x64/x86 build tools."
if errorlevel 1 exit /b 1
call :require_tool msbuild.exe "Install the Visual Studio 2022 MSVC v143 x64/x86 build tools."
if errorlevel 1 exit /b 1

if /i not "!VSCMD_ARG_HOST_ARCH!"=="x64" (
    echo ERROR: Visual Studio host architecture is not x64: !VSCMD_ARG_HOST_ARCH!
    exit /b 1
)
if /i not "!VSCMD_ARG_TGT_ARCH!"=="x64" (
    echo ERROR: Visual Studio target architecture is not x64: !VSCMD_ARG_TGT_ARCH!
    exit /b 1
)
if /i not "!WindowsSDKVersion!"=="!REQUIRED_WINDOWS_SDK!\" (
    echo ERROR: Windows SDK !REQUIRED_WINDOWS_SDK! was not selected.
    echo Actual WindowsSDKVersion: !WindowsSDKVersion!
    exit /b 1
)
if not defined VCToolsVersion (
    echo ERROR: Unable to determine the selected MSVC tools version.
    exit /b 1
)

set "WINDOWS_SDK_ACTUAL=!WindowsSDKVersion:\=!"

echo.
echo [zlib] Toolchain checks passed.
echo [zlib] zlib revision: !EXPECTED_ZLIB_TAG! / !ZLIB_COMMIT!
echo [zlib] MSVC tools: !VCToolsVersion!
echo [zlib] Windows SDK: !WINDOWS_SDK_ACTUAL!
echo [zlib] CMake: !CMAKE_VERSION!

if "!CHECK_ONLY!"=="1" (
    echo [zlib] Environment check completed successfully. No build was performed.
    exit /b 0
)

if /i "!BUILD_CONFIG!"=="all" (
    call :build_one Debug
    if errorlevel 1 exit /b 1
    call :build_one Release
    if errorlevel 1 exit /b 1
) else if /i "!BUILD_CONFIG!"=="debug" (
    call :build_one Debug
    if errorlevel 1 exit /b 1
) else (
    call :build_one Release
    if errorlevel 1 exit /b 1
)

echo.
echo [zlib] Requested build completed successfully.
echo [zlib] Build root: !ZLIB_BUILD_ROOT!
exit /b 0

:build_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_CONFIG_LOWER=%~1"
if /i "!CURRENT_CONFIG!"=="Debug" set "CURRENT_CONFIG_LOWER=debug"
if /i "!CURRENT_CONFIG!"=="Release" set "CURRENT_CONFIG_LOWER=release"

set "CURRENT_ROOT=!ZLIB_BUILD_ROOT!\x64-!CURRENT_CONFIG_LOWER!"
set "CURRENT_WORK=!CURRENT_ROOT!\work"
set "CURRENT_STAGE=!CURRENT_ROOT!\stage"

if "!CLEAN_BUILD!"=="1" (
    call :remove_exact_directory "!CURRENT_ROOT!" "!CURRENT_ROOT!"
    if errorlevel 1 exit /b 1
)

if not exist "!CURRENT_WORK!" mkdir "!CURRENT_WORK!"
if errorlevel 1 (
    echo ERROR: Failed to create zlib work directory: !CURRENT_WORK!
    exit /b 1
)

set "VS_ROOT_CMAKE=!VS_ROOT:\=/!"
set "CURRENT_STAGE_CMAKE=!CURRENT_STAGE:\=/!"

echo.
echo ==============================================================================
echo [zlib] Configuring !CURRENT_CONFIG! x64
echo [zlib] Work:  !CURRENT_WORK!
echo [zlib] Stage: !CURRENT_STAGE!
echo ==============================================================================

cmake -S "!ZLIB_CMAKE_DIR!" -B "!CURRENT_WORK!" ^
    -G "Visual Studio 17 2022" ^
    -A x64 ^
    "-DCMAKE_GENERATOR_INSTANCE=!VS_ROOT_CMAKE!" ^
    "-DCMAKE_SYSTEM_VERSION=!REQUIRED_WINDOWS_SDK!" ^
    "-DCMAKE_INSTALL_PREFIX=!CURRENT_STAGE_CMAKE!"
if errorlevel 1 (
    echo ERROR: zlib !CURRENT_CONFIG! CMake configuration failed.
    echo If this work directory used another generator or VS instance, rerun with clean.
    exit /b 1
)

echo.
echo [zlib] Building !CURRENT_CONFIG! x64...
cmake --build "!CURRENT_WORK!" --config !CURRENT_CONFIG! --parallel
if errorlevel 1 (
    echo ERROR: zlib !CURRENT_CONFIG! build failed.
    exit /b 1
)

echo.
echo [zlib] Running !CURRENT_CONFIG! CTest suite...
ctest --test-dir "!CURRENT_WORK!" -C !CURRENT_CONFIG! --output-on-failure
if errorlevel 1 (
    echo ERROR: zlib !CURRENT_CONFIG! CTest suite failed.
    exit /b 1
)

call :remove_exact_directory "!CURRENT_STAGE!" "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1

echo.
echo [zlib] Installing !CURRENT_CONFIG! stage...
cmake --install "!CURRENT_WORK!" --config !CURRENT_CONFIG! --prefix "!CURRENT_STAGE!"
if errorlevel 1 (
    echo ERROR: zlib !CURRENT_CONFIG! stage installation failed.
    exit /b 1
)

call :write_manifest !CURRENT_CONFIG! !CURRENT_CONFIG_LOWER! "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1
call :verify_stage !CURRENT_CONFIG! !CURRENT_CONFIG_LOWER! "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1

echo [zlib] !CURRENT_CONFIG! build, CTest, stage, and verification completed.
exit /b 0

:write_manifest
set "MANIFEST_CONFIG=%~1"
set "MANIFEST_CONFIG_LOWER=%~2"
set "MANIFEST_STAGE=%~3"
set "MANIFEST_DLL=!MANIFEST_STAGE!\bin\zlib1.dll"
set "MANIFEST_LIB=!MANIFEST_STAGE!\lib\zlib1.lib"
set "MANIFEST_FILE=!MANIFEST_STAGE!\build-manifest.txt"
set "MANIFEST_CRT=/MD"
if /i "!MANIFEST_CONFIG!"=="Debug" set "MANIFEST_CRT=/MDd"

set "HASH_OUTPUT=!MANIFEST_STAGE!\.zlib-hash.tmp"
set "DLL_SHA256="
certutil.exe -hashfile "!MANIFEST_DLL!" SHA256 >"!HASH_OUTPUT!" 2>nul
if errorlevel 1 (
    echo ERROR: certutil.exe failed to hash zlib1.dll.
    if exist "!HASH_OUTPUT!" del /q "!HASH_OUTPUT!"
    exit /b 1
)
for /f "usebackq skip=1 tokens=*" %%H in ("!HASH_OUTPUT!") do if not defined DLL_SHA256 set "DLL_SHA256=%%H"
del /q "!HASH_OUTPUT!"
if "!DLL_SHA256:~63,1!"=="" (
    echo ERROR: Unable to calculate zlib1.dll SHA-256.
    exit /b 1
)
if not "!DLL_SHA256:~64,1!"=="" (
    echo ERROR: Unexpected zlib1.dll SHA-256 output: !DLL_SHA256!
    exit /b 1
)

set "LIB_SHA256="
certutil.exe -hashfile "!MANIFEST_LIB!" SHA256 >"!HASH_OUTPUT!" 2>nul
if errorlevel 1 (
    echo ERROR: certutil.exe failed to hash zlib1.lib.
    if exist "!HASH_OUTPUT!" del /q "!HASH_OUTPUT!"
    exit /b 1
)
for /f "usebackq skip=1 tokens=*" %%H in ("!HASH_OUTPUT!") do if not defined LIB_SHA256 set "LIB_SHA256=%%H"
del /q "!HASH_OUTPUT!"
if "!LIB_SHA256:~63,1!"=="" (
    echo ERROR: Unable to calculate zlib1.lib SHA-256.
    exit /b 1
)
if not "!LIB_SHA256:~64,1!"=="" (
    echo ERROR: Unexpected zlib1.lib SHA-256 output: !LIB_SHA256!
    exit /b 1
)

> "!MANIFEST_FILE!" echo zlib tag: !EXPECTED_ZLIB_TAG!
>>"!MANIFEST_FILE!" echo zlib commit: !ZLIB_COMMIT!
>>"!MANIFEST_FILE!" echo Configuration: !MANIFEST_CONFIG!
>>"!MANIFEST_FILE!" echo Architecture: x64
>>"!MANIFEST_FILE!" echo Visual Studio: !VS_EDITION! 2022
>>"!MANIFEST_FILE!" echo MSVC tools: !VCToolsVersion!
>>"!MANIFEST_FILE!" echo Windows SDK: !WINDOWS_SDK_ACTUAL!
>>"!MANIFEST_FILE!" echo CMake: !CMAKE_VERSION!
>>"!MANIFEST_FILE!" echo CRT: !MANIFEST_CRT!
>>"!MANIFEST_FILE!" echo Library type: shared
>>"!MANIFEST_FILE!" echo DLL name: zlib1.dll
>>"!MANIFEST_FILE!" echo Import library: zlib1.lib
>>"!MANIFEST_FILE!" echo Tests: CTest passed
>>"!MANIFEST_FILE!" echo Contrib libraries: disabled
>>"!MANIFEST_FILE!" echo zlib1.dll SHA-256: !DLL_SHA256!
>>"!MANIFEST_FILE!" echo zlib1.lib SHA-256: !LIB_SHA256!
if errorlevel 1 (
    echo ERROR: Failed to write zlib build manifest: !MANIFEST_FILE!
    exit /b 1
)
exit /b 0

:verify_stage
set "VERIFY_CONFIG=%~1"
set "VERIFY_CONFIG_LOWER=%~2"
set "VERIFY_STAGE=%~3"

for %%F in (
    "!VERIFY_STAGE!\bin\zlib1.dll"
    "!VERIFY_STAGE!\include\zlib.h"
    "!VERIFY_STAGE!\include\zconf.h"
    "!VERIFY_STAGE!\lib\zlib1.lib"
    "!VERIFY_STAGE!\build-manifest.txt"
) do (
    if not exist "%%~fF" (
        echo ERROR: Expected staged artifact is missing: %%~fF
        exit /b 1
    )
)

findstr /x /c:"zlib tag: !EXPECTED_ZLIB_TAG!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: zlib stage manifest has an unexpected tag.
    exit /b 1
)
findstr /x /c:"zlib commit: !EXPECTED_ZLIB_COMMIT!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: zlib stage manifest has an unexpected commit.
    exit /b 1
)
findstr /x /c:"Configuration: !VERIFY_CONFIG!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: zlib stage manifest has an unexpected configuration.
    exit /b 1
)
findstr /x /c:"Windows SDK: !REQUIRED_WINDOWS_SDK!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: zlib stage manifest has an unexpected Windows SDK.
    exit /b 1
)

dumpbin /headers "!VERIFY_STAGE!\bin\zlib1.dll" | findstr /i /c:"8664 machine (x64)" >nul
if errorlevel 1 (
    echo ERROR: Staged zlib1.dll is not an x64 DLL.
    exit /b 1
)
dumpbin /exports "!VERIFY_STAGE!\bin\zlib1.dll" | findstr /c:" zlibVersion" >nul
if errorlevel 1 (
    echo ERROR: Staged zlib1.dll does not export zlibVersion.
    exit /b 1
)
dumpbin /exports "!VERIFY_STAGE!\bin\zlib1.dll" | findstr /c:" deflate" >nul
if errorlevel 1 (
    echo ERROR: Staged zlib1.dll does not export deflate APIs.
    exit /b 1
)

set "ZLIB_VERIFY_DLL=!VERIFY_STAGE!\bin\zlib1.dll"
"!WINDOWS_POWERSHELL!" -NoProfile -Command "$version=(Get-Item -LiteralPath $env:ZLIB_VERIFY_DLL).VersionInfo.FileVersion; if ($version -ne '1.3.2') { Write-Error ('Unexpected zlib DLL file version: ' + $version); exit 1 }"
if errorlevel 1 (
    echo ERROR: Staged zlib1.dll does not report file version 1.3.2.
    exit /b 1
)

dumpbin /dependents "!VERIFY_STAGE!\bin\zlib1.dll" | findstr /i /c:"VCRUNTIME140D.dll" /c:"VCRUNTIME140_1D.dll" /c:"ucrtbased.dll" >nul
if /i "!VERIFY_CONFIG!"=="Release" (
    if not errorlevel 1 (
        echo ERROR: Release zlib1.dll unexpectedly depends on the Debug CRT.
        exit /b 1
    )
) else (
    if errorlevel 1 (
        echo ERROR: Debug zlib1.dll does not depend on the expected Debug CRT.
        exit /b 1
    )
)

if exist "!VERIFY_STAGE!\bin\zlib1d.dll" (
    echo ERROR: Debug-postfix DLL leaked into the stage: !VERIFY_STAGE!\bin\zlib1d.dll
    exit /b 1
)
if exist "!VERIFY_STAGE!\lib\zlib1d.lib" (
    echo ERROR: Debug-postfix import library leaked into the stage: !VERIFY_STAGE!\lib\zlib1d.lib
    exit /b 1
)
if exist "!VERIFY_STAGE!\lib\zs.lib" (
    echo ERROR: Static zlib library leaked into the stage: !VERIFY_STAGE!\lib\zs.lib
    exit /b 1
)
for %%P in (minizip puff blast iostream testzlib infback9 zlibstatic) do (
    dir /s /b "!VERIFY_STAGE!\*%%P*" >nul 2>&1
    if not errorlevel 1 (
        echo ERROR: Excluded contrib or static artifact matching %%P exists in !VERIFY_STAGE!.
        exit /b 1
    )
)
exit /b 0

:check_cmake_version
set "CMAKE_VERSION="
for /f "tokens=3" %%V in ('cmake --version ^| findstr /b /c:"cmake version"') do set "CMAKE_VERSION=%%V"
if not defined CMAKE_VERSION (
    echo ERROR: Unable to determine the CMake version.
    exit /b 1
)
for /f "tokens=1,2 delims=." %%A in ("!CMAKE_VERSION!") do (
    set "CMAKE_VERSION_MAJOR=%%A"
    set "CMAKE_VERSION_MINOR=%%B"
)
if !CMAKE_VERSION_MAJOR! LSS 3 (
    echo ERROR: CMake 3.21 or newer is required. Found !CMAKE_VERSION!.
    exit /b 1
)
if !CMAKE_VERSION_MAJOR! EQU 3 if !CMAKE_VERSION_MINOR! LSS 21 (
    echo ERROR: CMake 3.21 or newer is required. Found !CMAKE_VERSION!.
    exit /b 1
)
exit /b 0

:remove_exact_directory
set "REMOVE_TARGET=%~f1"
set "ALLOWED_TARGET=%~f2"
if /i not "!REMOVE_TARGET!"=="!ALLOWED_TARGET!" (
    echo ERROR: Refusing to remove an unexpected directory.
    echo Target:  !REMOVE_TARGET!
    echo Allowed: !ALLOWED_TARGET!
    exit /b 1
)
if exist "!REMOVE_TARGET!" (
    echo [zlib] Removing: !REMOVE_TARGET!
    rmdir /s /q "!REMOVE_TARGET!"
    if exist "!REMOVE_TARGET!" (
        echo ERROR: Failed to remove: !REMOVE_TARGET!
        exit /b 1
    )
)
exit /b 0

:find_visual_studio
set "VS_ROOT="
set "VS_EDITION="
set "VS_DEVCMD="

for %%E in (Enterprise Professional Community) do (
    if not defined VS_ROOT (
        if exist "C:\Program Files\Microsoft Visual Studio\2022\%%E\Common7\Tools\VsDevCmd.bat" (
            set "VS_ROOT=C:\Program Files\Microsoft Visual Studio\2022\%%E"
            set "VS_EDITION=%%E"
        )
    )
)

if not defined VS_ROOT (
    echo ERROR: Visual Studio 2022 was not found in a supported default directory.
    echo Checked:
    echo   C:\Program Files\Microsoft Visual Studio\2022\Enterprise
    echo   C:\Program Files\Microsoft Visual Studio\2022\Professional
    echo   C:\Program Files\Microsoft Visual Studio\2022\Community
    echo Install Visual Studio 2022 with Desktop development with C++ and SDK !REQUIRED_WINDOWS_SDK!.
    exit /b 1
)

set "VS_DEVCMD=!VS_ROOT!\Common7\Tools\VsDevCmd.bat"
exit /b 0

:require_tool
where.exe "%~1" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Required tool was not found in PATH: %~1
    echo %~2
    exit /b 1
)
exit /b 0

:show_help
echo SQLiteBrowser zlib 1.3.2 Windows x64 build script
echo.
echo Usage:
echo   third_party\zlib\build.cmd [all^|debug^|release] [clean]
echo   third_party\zlib\build.cmd [all^|debug^|release] check
echo   third_party\zlib\build.cmd --help
echo.
echo Defaults:
echo   all
echo.
echo Build selection:
echo   all       Build, test, stage, and verify Debug and Release.
echo   debug     Build, test, stage, and verify Debug only.
echo   release   Build, test, stage, and verify Release only.
echo.
echo Other options:
echo   clean     Remove the selected zlib work and stage directories before building.
echo   check     Validate source and toolchain without building.
echo.
echo Stage directories:
echo   build\zlib\x64-debug\stage
echo   build\zlib\x64-release\stage
echo.
echo Every build runs CTest. The first version has no skip-test mode.
exit /b 0

:show_help_error
call :show_help
exit /b 1
