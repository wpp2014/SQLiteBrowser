@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "PROJECT_ROOT=%%~fI"
for %%I in ("%SCRIPT_DIR%.") do set "SQLCIPHER_CMAKE_DIR=%%~fI"

set "SQLCIPHER_SRC=%SCRIPT_DIR%src"
set "SQLCIPHER_CMAKE_BUILD=%PROJECT_ROOT%\build\sqlcipher-cmake"
set "SQLCIPHER_BUILD_ROOT=%PROJECT_ROOT%\build\sqlcipher"
set "OPENSSL_BUILD_ROOT=%PROJECT_ROOT%\build\openssl"
set "EXPECTED_SQLCIPHER_COMMIT=63697beb0fafcb61faa7a3e6fd267036548ab11b"
set "EXPECTED_SQLCIPHER_TAG=v4.18.0"
set "EXPECTED_OPENSSL_COMMIT=8cf17aaeb4599f8af87fefd810b5b5fee90fe69e"
set "EXPECTED_OPENSSL_TAG=openssl-3.5.7"
set "REQUIRED_WINDOWS_SDK=10.0.22621.0"

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

echo [SQLCipher] Project root:  !PROJECT_ROOT!
echo [SQLCipher] Source:        !SQLCIPHER_SRC!
echo [SQLCipher] Configuration: !BUILD_CONFIG!
if "!CLEAN_BUILD!"=="1" echo [SQLCipher] Clean rebuild: yes
if "!CHECK_ONLY!"=="1" echo [SQLCipher] Check only: yes
echo.

echo(!PROJECT_ROOT!| findstr /r /c:"[ 	]" >nul
if not errorlevel 1 (
    echo ERROR: The SQLCipher wrapper does not support repository paths containing spaces.
    echo Path: !PROJECT_ROOT!
    exit /b 1
)

call :require_tool git.exe "Install Git and add git.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool cmake.exe "Install CMake 3.21 or newer and add cmake.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool powershell.exe "Windows PowerShell is required to launch the generated SQLCipher build batch file."
if errorlevel 1 exit /b 1

call :check_cmake_version
if errorlevel 1 exit /b 1

if not exist "!SQLCIPHER_SRC!\Makefile.msc" (
    if "!CHECK_ONLY!"=="1" (
        echo ERROR: The SQLCipher submodule is not initialised: !SQLCIPHER_SRC!
        echo Run: git submodule update --init --recursive
        exit /b 1
    )

    echo [SQLCipher] Initialising the SQLCipher submodule...
    git -C "!PROJECT_ROOT!" submodule update --init --recursive -- third_party/sqlcipher/src
    if errorlevel 1 (
        echo ERROR: Failed to initialise the SQLCipher submodule.
        exit /b 1
    )
)

if not exist "!SQLCIPHER_SRC!\Makefile.msc" (
    echo ERROR: SQLCipher Makefile.msc is missing after submodule initialisation.
    exit /b 1
)
if not exist "!SQLCIPHER_SRC!\src\sqlcipher.c" (
    echo ERROR: SQLCipher codec source is missing after submodule initialisation.
    exit /b 1
)

set "SQLCIPHER_COMMIT="
for /f "usebackq delims=" %%I in (`git -C "!SQLCIPHER_SRC!" rev-parse HEAD 2^>nul`) do set "SQLCIPHER_COMMIT=%%I"
if not defined SQLCIPHER_COMMIT (
    echo ERROR: Unable to read the SQLCipher submodule commit.
    exit /b 1
)
if /i not "!SQLCIPHER_COMMIT!"=="!EXPECTED_SQLCIPHER_COMMIT!" (
    echo ERROR: Unexpected SQLCipher submodule commit.
    echo Expected: !EXPECTED_SQLCIPHER_COMMIT! ^(!EXPECTED_SQLCIPHER_TAG!^)
    echo Actual:   !SQLCIPHER_COMMIT!
    echo Refusing to build an unverified SQLCipher revision.
    exit /b 1
)

set "SQLCIPHER_DIRTY="
for /f "usebackq delims=" %%I in (`git -C "!SQLCIPHER_SRC!" status --porcelain=v1 --untracked-files=all --ignore-submodules=all 2^>nul`) do set "SQLCIPHER_DIRTY=1"
if defined SQLCIPHER_DIRTY (
    echo ERROR: The SQLCipher source submodule has local changes.
    echo Commit, stash, or remove those changes before building.
    git -C "!SQLCIPHER_SRC!" status --short --ignore-submodules=all
    exit /b 1
)

call :find_visual_studio
if errorlevel 1 exit /b 1

echo [SQLCipher] Visual Studio: !VS_EDITION! 2022
echo [SQLCipher] Initialising MSVC x64 with Windows SDK !REQUIRED_WINDOWS_SDK!...
call "!VS_DEVCMD!" -no_logo -arch=x64 -host_arch=x64 -winsdk=!REQUIRED_WINDOWS_SDK!
if errorlevel 1 (
    echo ERROR: Visual Studio developer environment initialisation failed.
    exit /b 1
)

call :require_tool cl.exe "Install the Visual Studio 2022 Desktop development with C++ workload."
if errorlevel 1 exit /b 1
call :require_tool nmake.exe "Install the Visual Studio 2022 MSVC v143 x64/x86 build tools."
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

if /i "!BUILD_CONFIG!"=="all" (
    call :check_openssl debug
    if errorlevel 1 exit /b 1
    call :check_openssl release
    if errorlevel 1 exit /b 1
) else (
    call :check_openssl !BUILD_CONFIG!
    if errorlevel 1 exit /b 1
)

echo.
echo [SQLCipher] Toolchain and dependency checks passed.
echo [SQLCipher] SQLCipher revision: !EXPECTED_SQLCIPHER_TAG! / !SQLCIPHER_COMMIT!
echo [SQLCipher] MSVC tools: !VCToolsVersion!
echo [SQLCipher] Windows SDK: !WindowsSDKVersion!
echo [SQLCipher] CMake: !CMAKE_VERSION!

if "!CHECK_ONLY!"=="1" (
    echo [SQLCipher] Environment check completed successfully. No build was performed.
    exit /b 0
)

if "!CLEAN_BUILD!"=="1" (
    call :remove_exact_directory "!SQLCIPHER_CMAKE_BUILD!" "!SQLCIPHER_CMAKE_BUILD!"
    if errorlevel 1 exit /b 1
    if /i "!BUILD_CONFIG!"=="all" (
        call :remove_exact_directory "!SQLCIPHER_BUILD_ROOT!\x64-debug" "!SQLCIPHER_BUILD_ROOT!\x64-debug"
        if errorlevel 1 exit /b 1
        call :remove_exact_directory "!SQLCIPHER_BUILD_ROOT!\x64-release" "!SQLCIPHER_BUILD_ROOT!\x64-release"
        if errorlevel 1 exit /b 1
    ) else (
        call :remove_exact_directory "!SQLCIPHER_BUILD_ROOT!\x64-!BUILD_CONFIG!" "!SQLCIPHER_BUILD_ROOT!\x64-!BUILD_CONFIG!"
        if errorlevel 1 exit /b 1
    )
)

set "VS_ROOT_CMAKE=!VS_ROOT:\=/!"
echo.
echo [SQLCipher] Configuring CMake wrapper...
cmake -S "!SQLCIPHER_CMAKE_DIR!" -B "!SQLCIPHER_CMAKE_BUILD!" ^
    -G "Visual Studio 17 2022" ^
    -A x64 ^
    "-DCMAKE_GENERATOR_INSTANCE=!VS_ROOT_CMAKE!" ^
    "-DCMAKE_SYSTEM_VERSION=!REQUIRED_WINDOWS_SDK!" ^
    "-DSQLCIPHER_BUILD_CLI=ON"
if errorlevel 1 (
    echo ERROR: SQLCipher CMake configuration failed.
    echo If the build directory was configured with a different Visual Studio instance, rerun with clean.
    exit /b 1
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
echo [SQLCipher] Requested build completed successfully.
echo [SQLCipher] Build root: !SQLCIPHER_BUILD_ROOT!
echo [SQLCipher] NOTE: The product wrapper performs artifact and provider smoke checks, not the Tcl SQLCipher test suite.
exit /b 0

:build_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_CONFIG_LOWER=%~1"
if /i "!CURRENT_CONFIG!"=="Debug" set "CURRENT_CONFIG_LOWER=debug"
if /i "!CURRENT_CONFIG!"=="Release" set "CURRENT_CONFIG_LOWER=release"

echo.
echo ================================================================================
echo [SQLCipher] Building !CURRENT_CONFIG! x64
echo [SQLCipher] Stage: !SQLCIPHER_BUILD_ROOT!\x64-!CURRENT_CONFIG_LOWER!\stage
echo ================================================================================

cmake --build "!SQLCIPHER_CMAKE_BUILD!" --config !CURRENT_CONFIG! --target sqlcipher_stage
if errorlevel 1 (
    echo ERROR: SQLCipher !CURRENT_CONFIG! build failed.
    exit /b 1
)

call :verify_stage !CURRENT_CONFIG_LOWER!
if errorlevel 1 exit /b 1
echo [SQLCipher] !CURRENT_CONFIG! build and stage verification completed.
exit /b 0

:verify_stage
set "VERIFY_CONFIG=%~1"
set "VERIFY_STAGE=!SQLCIPHER_BUILD_ROOT!\x64-!VERIFY_CONFIG!\stage"

for %%F in (
    "!VERIFY_STAGE!\bin\sqlcipher.dll"
    "!VERIFY_STAGE!\bin\sqlcipher.exe"
    "!VERIFY_STAGE!\include\sqlcipher\sqlite3.h"
    "!VERIFY_STAGE!\include\sqlcipher\sqlite3ext.h"
    "!VERIFY_STAGE!\include\sqlcipher\sqlite3session.h"
    "!VERIFY_STAGE!\lib\sqlcipher.lib"
    "!VERIFY_STAGE!\build-manifest.txt"
) do (
    if not exist "%%~fF" (
        echo ERROR: Expected staged artifact is missing: %%~fF
        exit /b 1
    )
)

findstr /x /c:"SQLCipher tag: !EXPECTED_SQLCIPHER_TAG!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: SQLCipher stage manifest has an unexpected tag.
    exit /b 1
)
findstr /x /c:"SQLCipher commit: !EXPECTED_SQLCIPHER_COMMIT!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: SQLCipher stage manifest has an unexpected commit.
    exit /b 1
)
set "VERIFY_CONFIG_NAME=Release"
if /i "!VERIFY_CONFIG!"=="debug" set "VERIFY_CONFIG_NAME=Debug"
findstr /x /c:"Configuration: !VERIFY_CONFIG_NAME!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: SQLCipher stage manifest has an unexpected configuration.
    exit /b 1
)
findstr /i /c:"openssl" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: SQLCipher stage manifest does not identify the OpenSSL provider.
    exit /b 1
)
findstr /i /c:"OpenSSL 3.5.7" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: SQLCipher stage manifest does not contain the expected OpenSSL version.
    exit /b 1
)
dumpbin /exports "!VERIFY_STAGE!\bin\sqlcipher.dll" | findstr /c:" sqlcipher_version" >nul
if errorlevel 1 (
    echo ERROR: SQLCipher DLL does not export sqlcipher_version.
    exit /b 1
)
exit /b 0

:check_openssl
set "OPENSSL_CONFIG=%~1"
set "OPENSSL_STAGE=!OPENSSL_BUILD_ROOT!\x64-!OPENSSL_CONFIG!\stage"

for %%F in (
    "!OPENSSL_STAGE!\bin\openssl.exe"
    "!OPENSSL_STAGE!\bin\libcrypto-3-x64.dll"
    "!OPENSSL_STAGE!\include\openssl\opensslv.h"
    "!OPENSSL_STAGE!\lib\libcrypto.lib"
) do (
    if not exist "%%~fF" (
        echo ERROR: Required !OPENSSL_CONFIG! OpenSSL artifact is missing: %%~fF
        echo Build it first with: third_party\openssl\build.cmd !OPENSSL_CONFIG! safe
        exit /b 1
    )
)

"!OPENSSL_STAGE!\bin\openssl.exe" version | findstr /i /c:"OpenSSL 3.5.7" >nul
if errorlevel 1 (
    echo ERROR: The !OPENSSL_CONFIG! OpenSSL stage is not OpenSSL 3.5.7.
    exit /b 1
)

dumpbin /dependents "!OPENSSL_STAGE!\bin\libcrypto-3-x64.dll" | findstr /i /c:"VCRUNTIME140D.dll" /c:"VCRUNTIME140_1D.dll" /c:"ucrtbased.dll" >nul
if /i "!OPENSSL_CONFIG!"=="release" (
    if not errorlevel 1 (
        echo ERROR: Release OpenSSL unexpectedly depends on the Debug CRT.
        exit /b 1
    )
) else (
    if errorlevel 1 (
        echo ERROR: Debug OpenSSL does not depend on the expected Debug CRT.
        exit /b 1
    )
)

set "OPENSSL_MANIFEST=!OPENSSL_STAGE!\build-manifest.txt"
if exist "!OPENSSL_MANIFEST!" (
    findstr /x /c:"OpenSSL tag: !EXPECTED_OPENSSL_TAG!" "!OPENSSL_MANIFEST!" >nul
    if errorlevel 1 (
        echo ERROR: The !OPENSSL_CONFIG! OpenSSL manifest has an unexpected tag.
        exit /b 1
    )
    findstr /x /c:"OpenSSL commit: !EXPECTED_OPENSSL_COMMIT!" "!OPENSSL_MANIFEST!" >nul
    if errorlevel 1 (
        echo ERROR: The !OPENSSL_CONFIG! OpenSSL manifest has an unexpected commit.
        exit /b 1
    )
    findstr /x /c:"Configuration: !OPENSSL_CONFIG!" "!OPENSSL_MANIFEST!" >nul
    if errorlevel 1 (
        echo ERROR: The !OPENSSL_CONFIG! OpenSSL manifest has an unexpected configuration.
        exit /b 1
    )
    findstr /b /c:"Windows SDK: !REQUIRED_WINDOWS_SDK!" "!OPENSSL_MANIFEST!" >nul
    if errorlevel 1 (
        echo ERROR: The !OPENSSL_CONFIG! OpenSSL manifest has an unexpected Windows SDK.
        exit /b 1
    )
) else (
    echo [SQLCipher] WARNING: OpenSSL !OPENSSL_CONFIG! stage has no build-manifest.txt.
    echo [SQLCipher]          Development builds may continue, but recreate it before a formal release.
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
    echo [SQLCipher] Removing: !REMOVE_TARGET!
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
echo SQLiteBrowser SQLCipher 4.18.0 Windows x64 build script
echo.
echo Usage:
echo   third_party\sqlcipher\build.cmd [all^|debug^|release] [clean]
echo   third_party\sqlcipher\build.cmd [all^|debug^|release] check
echo   third_party\sqlcipher\build.cmd --help
echo.
echo Defaults:
echo   all
echo.
echo Build selection:
echo   all       Build Debug and Release.
echo   debug     Build Debug only.
echo   release   Build Release only.
echo.
echo Other options:
echo   clean     Remove the shared CMake build and selected SQLCipher work/stage directories first.
echo   check     Validate source, toolchain, and matching OpenSSL stages without building.
echo.
echo Required OpenSSL stages:
echo   build\openssl\x64-debug\stage
echo   build\openssl\x64-release\stage
echo.
echo SQLCipher stage directories:
echo   build\sqlcipher\x64-debug\stage
echo   build\sqlcipher\x64-release\stage
exit /b 0

:show_help_error
call :show_help
exit /b 1
