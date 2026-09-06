@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "PROJECT_ROOT=%%~fI"
for %%I in ("%SCRIPT_DIR%.") do set "ZSTD_CMAKE_DIR=%%~fI"

set "ZSTD_SRC=%SCRIPT_DIR%src"
set "OUTPUT_ROOT=%PROJECT_ROOT%\output"
set "EXPECTED_ZSTD_COMMIT=f8745da6ff1ad1e7bab384bd1f9d742439278e99"
set "EXPECTED_ZSTD_TAG=v1.5.7"
set "EXPECTED_ZSTD_VERSION=1.5.7"
set "REQUIRED_WINDOWS_SDK=10.0.26100.0"
set "WINDOWS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

set "ACTION=build"
set "ACTION_EXPLICIT=0"
set "BUILD_CONFIG=all"

:parse_arguments
if "%~1"=="" goto arguments_parsed

if /i "%~1"=="build" (
    call :set_action build
    if errorlevel 1 exit /b 1
) else if /i "%~1"=="test" (
    call :set_action test
    if errorlevel 1 exit /b 1
) else if /i "%~1"=="clean" (
    call :set_action clean
    if errorlevel 1 exit /b 1
) else if /i "%~1"=="check" (
    call :set_action check
    if errorlevel 1 exit /b 1
) else if /i "%~1"=="all" (
    set "BUILD_CONFIG=all"
) else if /i "%~1"=="debug" (
    set "BUILD_CONFIG=debug"
) else if /i "%~1"=="release" (
    set "BUILD_CONFIG=release"
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
set "LC_ALL=C"
set "LANG=C"
set "LANGUAGE="
set "VSCMD_SKIP_SENDTELEMETRY=1"

echo [zstd] Project root:  !PROJECT_ROOT!
echo [zstd] Source:        !ZSTD_SRC!
echo [zstd] Action:        !ACTION!
echo [zstd] Configuration: !BUILD_CONFIG!
echo.

call :require_tool git.exe "Install Git and add git.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool cmake.exe "Install CMake 3.22 or newer and add cmake.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool ctest.exe "Install CMake with CTest and add ctest.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool certutil.exe "Windows certutil.exe is required to calculate artifact SHA-256 values."
if errorlevel 1 exit /b 1
if not exist "!WINDOWS_POWERSHELL!" (
    echo ERROR: Windows PowerShell was not found at the required default path.
    echo Expected: !WINDOWS_POWERSHELL!
    exit /b 1
)

call :check_cmake_version
if errorlevel 1 exit /b 1

if not exist "!ZSTD_SRC!\build\cmake\CMakeLists.txt" (
    if /i "!ACTION!"=="check" (
        echo ERROR: The zstd submodule is not initialised: !ZSTD_SRC!
        echo Run: git submodule update --init --recursive
        exit /b 1
    )

    echo [zstd] Initialising the zstd submodule...
    git -C "!PROJECT_ROOT!" submodule update --init --recursive -- third_party/zstd/src
    if errorlevel 1 (
        echo ERROR: Failed to initialise the zstd submodule.
        exit /b 1
    )
)

if not exist "!ZSTD_SRC!\build\cmake\CMakeLists.txt" (
    echo ERROR: zstd build/cmake/CMakeLists.txt is missing after submodule initialisation.
    exit /b 1
)
if not exist "!ZSTD_SRC!\lib\zstd.h" (
    echo ERROR: zstd public headers are missing after submodule initialisation.
    exit /b 1
)

set "ZSTD_COMMIT="
for /f "usebackq delims=" %%I in (`git -C "!ZSTD_SRC!" rev-parse HEAD 2^>nul`) do set "ZSTD_COMMIT=%%I"
if not defined ZSTD_COMMIT (
    echo ERROR: Unable to read the zstd submodule commit.
    exit /b 1
)
if /i not "!ZSTD_COMMIT!"=="!EXPECTED_ZSTD_COMMIT!" (
    echo ERROR: Unexpected zstd submodule commit.
    echo Expected: !EXPECTED_ZSTD_COMMIT! ^(!EXPECTED_ZSTD_TAG!^)
    echo Actual:   !ZSTD_COMMIT!
    echo Refusing to build an unverified zstd revision.
    exit /b 1
)

set "ZSTD_TAG="
for /f "usebackq delims=" %%I in (`git -C "!ZSTD_SRC!" describe --tags --exact-match 2^>nul`) do set "ZSTD_TAG=%%I"
if /i not "!ZSTD_TAG!"=="!EXPECTED_ZSTD_TAG!" (
    echo ERROR: The zstd submodule is not checked out at tag !EXPECTED_ZSTD_TAG!.
    echo Actual tag: !ZSTD_TAG!
    exit /b 1
)

set "ZSTD_DIRTY="
for /f "usebackq delims=" %%I in (`git -C "!ZSTD_SRC!" status --porcelain=v1 --untracked-files=all --ignore-submodules=all 2^>nul`) do set "ZSTD_DIRTY=1"
if defined ZSTD_DIRTY (
    echo ERROR: The zstd source submodule has local changes.
    echo Commit, stash, or remove those changes before building.
    git -C "!ZSTD_SRC!" status --short --ignore-submodules=all
    exit /b 1
)

call :find_visual_studio
if errorlevel 1 exit /b 1

echo [zstd] Visual Studio: !VS_EDITION! 2022
echo [zstd] Initialising MSVC x64 with Windows SDK !REQUIRED_WINDOWS_SDK!...
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
echo [zstd] Toolchain checks passed.
echo [zstd] zstd revision: !EXPECTED_ZSTD_TAG! / !ZSTD_COMMIT!
echo [zstd] MSVC tools: !VCToolsVersion!
echo [zstd] Windows SDK: !WINDOWS_SDK_ACTUAL!
echo [zstd] CMake: !CMAKE_VERSION!

if /i "!ACTION!"=="check" (
    echo [zstd] Environment check completed successfully. No build was performed.
    exit /b 0
)

if /i "!ACTION!"=="clean" goto dispatch_clean
if /i "!ACTION!"=="test" goto dispatch_test

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
echo [zstd] Requested minimal product build completed successfully.
echo [zstd] Output root: !OUTPUT_ROOT!
exit /b 0

:dispatch_test
if /i "!BUILD_CONFIG!"=="all" (
    call :test_one Debug
    if errorlevel 1 exit /b 1
    call :test_one Release
    if errorlevel 1 exit /b 1
) else if /i "!BUILD_CONFIG!"=="debug" (
    call :test_one Debug
    if errorlevel 1 exit /b 1
) else (
    call :test_one Release
    if errorlevel 1 exit /b 1
)
echo [zstd] Requested tests completed successfully.
exit /b 0

:dispatch_clean
if /i "!BUILD_CONFIG!"=="all" (
    call :clean_one Debug
    if errorlevel 1 exit /b 1
    call :clean_one Release
    if errorlevel 1 exit /b 1
) else if /i "!BUILD_CONFIG!"=="debug" (
    call :clean_one Debug
    if errorlevel 1 exit /b 1
) else (
    call :clean_one Release
    if errorlevel 1 exit /b 1
)
echo [zstd] Requested clean completed successfully.
exit /b 0

:set_action
if "!ACTION_EXPLICIT!"=="1" if /i not "!ACTION!"=="%~1" (
    echo ERROR: Multiple actions were specified: !ACTION! and %~1.
    exit /b 1
)
set "ACTION=%~1"
set "ACTION_EXPLICIT=1"
exit /b 0

:require_tool
where.exe "%~1" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Required tool was not found in PATH: %~1
    echo %~2
    exit /b 1
)
exit /b 0

:build_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_CONFIG_LOWER=%~1"
if /i "!CURRENT_CONFIG!"=="Debug" set "CURRENT_CONFIG_LOWER=debug"
if /i "!CURRENT_CONFIG!"=="Release" set "CURRENT_CONFIG_LOWER=release"

set "CURRENT_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG_LOWER!\build\zstd"
set "CURRENT_WORK=!CURRENT_ROOT!\work"
set "CURRENT_STAGE=!CURRENT_ROOT!\stage"

if not exist "!CURRENT_WORK!" mkdir "!CURRENT_WORK!"
if errorlevel 1 (
    echo ERROR: Failed to create zstd work directory: !CURRENT_WORK!
    exit /b 1
)

set "VS_ROOT_CMAKE=!VS_ROOT:\=/!"
set "CURRENT_STAGE_CMAKE=!CURRENT_STAGE:\=/!"

echo.
echo ================================================================================
echo [zstd] Configuring !CURRENT_CONFIG! x64
echo [zstd] Work:  !CURRENT_WORK!
echo [zstd] Stage: !CURRENT_STAGE!
echo ================================================================================

cmake -S "!ZSTD_CMAKE_DIR!" -B "!CURRENT_WORK!" ^
    -G "Visual Studio 17 2022" ^
    -A x64 ^
    "-DCMAKE_GENERATOR_INSTANCE=!VS_ROOT_CMAKE!" ^
    "-DCMAKE_SYSTEM_VERSION=!REQUIRED_WINDOWS_SDK!" ^
    "-DCMAKE_INSTALL_PREFIX=!CURRENT_STAGE_CMAKE!" ^
    "-DZSTD_WINDOWS_SDK_VERSION=!REQUIRED_WINDOWS_SDK!"
if errorlevel 1 (
    echo ERROR: zstd !CURRENT_CONFIG! CMake configuration failed.
    echo If this work directory used another generator or VS instance, rerun with clean.
    exit /b 1
)

echo.
echo [zstd] Building !CURRENT_CONFIG! x64 product target...
cmake --build "!CURRENT_WORK!" --config !CURRENT_CONFIG! --parallel --target libzstd_shared
if errorlevel 1 (
    echo ERROR: zstd !CURRENT_CONFIG! build failed.
    exit /b 1
)

call :remove_exact_directory "!CURRENT_STAGE!" "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1

echo.
echo [zstd] Installing !CURRENT_CONFIG! stage...
cmake --install "!CURRENT_WORK!" --config !CURRENT_CONFIG! --prefix "!CURRENT_STAGE!"
if errorlevel 1 (
    echo ERROR: zstd !CURRENT_CONFIG! stage installation failed.
    exit /b 1
)

call :write_manifest !CURRENT_CONFIG! !CURRENT_CONFIG_LOWER! "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1
call :verify_stage !CURRENT_CONFIG! !CURRENT_CONFIG_LOWER! "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1

echo [zstd] !CURRENT_CONFIG! minimal build, stage, and verification completed.
exit /b 0

:test_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_CONFIG_LOWER=%~1"
if /i "!CURRENT_CONFIG!"=="Debug" set "CURRENT_CONFIG_LOWER=debug"
if /i "!CURRENT_CONFIG!"=="Release" set "CURRENT_CONFIG_LOWER=release"
set "CURRENT_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG_LOWER!\build\zstd"
set "CURRENT_WORK=!CURRENT_ROOT!\work"
set "CURRENT_STAGE=!CURRENT_ROOT!\stage"
if not exist "!CURRENT_WORK!\CMakeCache.txt" (
    echo ERROR: zstd !CURRENT_CONFIG! has not been configured.
    echo Run: third_party\zstd\build.cmd build !CURRENT_CONFIG_LOWER!
    exit /b 1
)
call :verify_stage !CURRENT_CONFIG! !CURRENT_CONFIG_LOWER! "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1
echo [zstd] Building !CURRENT_CONFIG! test-only target...
cmake --build "!CURRENT_WORK!" --config !CURRENT_CONFIG! --parallel --target zstd_shared_smoke
if errorlevel 1 exit /b 1
echo [zstd] Running !CURRENT_CONFIG! shared-library smoke test...
ctest --test-dir "!CURRENT_WORK!" -C !CURRENT_CONFIG! -R "^zstd\.shared\.smoke$" --output-on-failure
if errorlevel 1 exit /b 1
call :write_test_manifest !CURRENT_CONFIG! "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1
echo [zstd] !CURRENT_CONFIG! test completed; product artifacts were not reinstalled.
exit /b 0

:clean_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_CONFIG_LOWER=%~1"
if /i "!CURRENT_CONFIG!"=="Debug" set "CURRENT_CONFIG_LOWER=debug"
if /i "!CURRENT_CONFIG!"=="Release" set "CURRENT_CONFIG_LOWER=release"
set "CURRENT_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG_LOWER!\build\zstd"
call :remove_exact_directory "!CURRENT_ROOT!" "!CURRENT_ROOT!"
exit /b !ERRORLEVEL!

:write_manifest
set "MANIFEST_CONFIG=%~1"
set "MANIFEST_CONFIG_LOWER=%~2"
set "MANIFEST_STAGE=%~3"
set "MANIFEST_DLL=!MANIFEST_STAGE!\bin\libzstd.dll"
set "MANIFEST_PDB=!MANIFEST_STAGE!\bin\libzstd.pdb"
set "MANIFEST_LIB=!MANIFEST_STAGE!\lib\libzstd.lib"
set "MANIFEST_FILE=!MANIFEST_STAGE!\build-manifest.txt"
set "MANIFEST_CRT=/MD"
if /i "!MANIFEST_CONFIG!"=="Debug" set "MANIFEST_CRT=/MDd"

call :calculate_sha256 "!MANIFEST_DLL!" DLL_SHA256
if errorlevel 1 exit /b 1
call :calculate_sha256 "!MANIFEST_PDB!" PDB_SHA256
if errorlevel 1 exit /b 1
call :calculate_sha256 "!MANIFEST_LIB!" LIB_SHA256
if errorlevel 1 exit /b 1

>"!MANIFEST_FILE!" echo zstd tag: !EXPECTED_ZSTD_TAG!
>>"!MANIFEST_FILE!" echo zstd commit: !ZSTD_COMMIT!
>>"!MANIFEST_FILE!" echo Configuration: !MANIFEST_CONFIG!
>>"!MANIFEST_FILE!" echo Architecture: x64
>>"!MANIFEST_FILE!" echo Visual Studio: !VS_EDITION! 2022
>>"!MANIFEST_FILE!" echo MSVC tools: !VCToolsVersion!
>>"!MANIFEST_FILE!" echo Windows SDK: !WINDOWS_SDK_ACTUAL!
>>"!MANIFEST_FILE!" echo CMake: !CMAKE_VERSION!
>>"!MANIFEST_FILE!" echo CRT: !MANIFEST_CRT!
>>"!MANIFEST_FILE!" echo Library type: shared
>>"!MANIFEST_FILE!" echo DLL name: libzstd.dll
>>"!MANIFEST_FILE!" echo Import library: libzstd.lib
>>"!MANIFEST_FILE!" echo Linker PDB: libzstd.pdb
>>"!MANIFEST_FILE!" echo PDB policy: linker PDB staged; compiler PDB excluded
>>"!MANIFEST_FILE!" echo Release symbol flags: /Zi /DEBUG:FULL /OPT:REF /OPT:ICF
>>"!MANIFEST_FILE!" echo Compression support: ON
>>"!MANIFEST_FILE!" echo Decompression support: ON
>>"!MANIFEST_FILE!" echo Dictionary builder: ON
>>"!MANIFEST_FILE!" echo Deprecated APIs: OFF
>>"!MANIFEST_FILE!" echo Legacy support: OFF
>>"!MANIFEST_FILE!" echo Multithread support: ON
>>"!MANIFEST_FILE!" echo ZSTD_ZLIB_SUPPORT: OFF
>>"!MANIFEST_FILE!" echo ZSTD_LZMA_SUPPORT: OFF
>>"!MANIFEST_FILE!" echo ZSTD_LZ4_SUPPORT: OFF
>>"!MANIFEST_FILE!" echo Project shared smoke test: not run
>>"!MANIFEST_FILE!" echo Upstream static tests: not run
>>"!MANIFEST_FILE!" echo Runtime version verification: not run
>>"!MANIFEST_FILE!" echo libzstd.dll SHA-256: !DLL_SHA256!
>>"!MANIFEST_FILE!" echo libzstd.pdb SHA-256: !PDB_SHA256!
>>"!MANIFEST_FILE!" echo libzstd.lib SHA-256: !LIB_SHA256!
if errorlevel 1 (
    echo ERROR: Failed to write zstd build manifest: !MANIFEST_FILE!
    exit /b 1
)
exit /b 0

:write_test_manifest
set "TEST_CONFIG=%~1"
set "TEST_STAGE=%~2"
call :calculate_sha256 "!TEST_STAGE!\build-manifest.txt" BUILD_MANIFEST_SHA256
if errorlevel 1 exit /b 1
>"!TEST_STAGE!\test-manifest.txt" echo zstd tag: !EXPECTED_ZSTD_TAG!
>>"!TEST_STAGE!\test-manifest.txt" echo zstd commit: !ZSTD_COMMIT!
>>"!TEST_STAGE!\test-manifest.txt" echo Configuration: !TEST_CONFIG!
>>"!TEST_STAGE!\test-manifest.txt" echo Build manifest SHA-256: !BUILD_MANIFEST_SHA256!
>>"!TEST_STAGE!\test-manifest.txt" echo Project shared smoke test: passed
>>"!TEST_STAGE!\test-manifest.txt" echo Runtime version: !EXPECTED_ZSTD_VERSION!
>>"!TEST_STAGE!\test-manifest.txt" echo Upstream static tests: not run
if errorlevel 1 exit /b 1
exit /b 0

:calculate_sha256
set "HASH_FILE=%~1"
set "HASH_RESULT_VARIABLE=%~2"
set "HASH_OUTPUT=%TEMP%\sqlitebrowser-zstd-hash-!RANDOM!-!RANDOM!.tmp"
set "HASH_VALUE="

if not exist "!HASH_FILE!" (
    echo ERROR: Cannot hash missing file: !HASH_FILE!
    exit /b 1
)

certutil.exe -hashfile "!HASH_FILE!" SHA256 >"!HASH_OUTPUT!" 2>nul
if errorlevel 1 (
    echo ERROR: certutil.exe failed to hash: !HASH_FILE!
    if exist "!HASH_OUTPUT!" del /q "!HASH_OUTPUT!"
    exit /b 1
)
for /f "usebackq skip=1 tokens=*" %%H in ("!HASH_OUTPUT!") do if not defined HASH_VALUE set "HASH_VALUE=%%H"
del /q "!HASH_OUTPUT!"

set "HASH_VALUE=!HASH_VALUE: =!"
if "!HASH_VALUE:~63,1!"=="" (
    echo ERROR: Unable to calculate SHA-256 for: !HASH_FILE!
    exit /b 1
)
if not "!HASH_VALUE:~64,1!"=="" (
    echo ERROR: Unexpected SHA-256 output for !HASH_FILE!: !HASH_VALUE!
    exit /b 1
)

set "!HASH_RESULT_VARIABLE!=!HASH_VALUE!"
exit /b 0

:verify_stage
set "VERIFY_CONFIG=%~1"
set "VERIFY_CONFIG_LOWER=%~2"
set "VERIFY_STAGE=%~3"

for %%F in (
    "!VERIFY_STAGE!\bin\libzstd.dll"
    "!VERIFY_STAGE!\bin\libzstd.pdb"
    "!VERIFY_STAGE!\include\zstd.h"
    "!VERIFY_STAGE!\include\zdict.h"
    "!VERIFY_STAGE!\include\zstd_errors.h"
    "!VERIFY_STAGE!\lib\libzstd.lib"
    "!VERIFY_STAGE!\build-manifest.txt"
) do (
    if not exist "%%~fF" (
        echo ERROR: Expected staged artifact is missing: %%~fF
        exit /b 1
    )
)

findstr /x /c:"zstd tag: !EXPECTED_ZSTD_TAG!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: zstd stage manifest has an unexpected tag.
    exit /b 1
)
findstr /x /c:"zstd commit: !EXPECTED_ZSTD_COMMIT!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: zstd stage manifest has an unexpected commit.
    exit /b 1
)
findstr /x /c:"Configuration: !VERIFY_CONFIG!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: zstd stage manifest has an unexpected configuration.
    exit /b 1
)
findstr /x /c:"Windows SDK: !REQUIRED_WINDOWS_SDK!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: zstd stage manifest has an unexpected Windows SDK.
    exit /b 1
)
findstr /x /c:"ZSTD_ZLIB_SUPPORT: OFF" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: zstd stage manifest does not record ZSTD_ZLIB_SUPPORT as OFF.
    exit /b 1
)
findstr /x /c:"Project shared smoke test: not run" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: zstd build manifest has an unexpected test status.
    exit /b 1
)

set "VERIFY_COMPILER_PDB="
for /r "!VERIFY_STAGE!" %%F in (vc143.pdb) do if exist "%%~fF" set "VERIFY_COMPILER_PDB=%%~fF"
if defined VERIFY_COMPILER_PDB (
    echo ERROR: Compiler PDB vc143.pdb must not be deployed to the zstd stage.
    exit /b 1
)

dumpbin /headers "!VERIFY_STAGE!\bin\libzstd.dll" | findstr /i /c:"8664 machine (x64)" >nul
if errorlevel 1 (
    echo ERROR: Staged libzstd.dll is not an x64 DLL.
    exit /b 1
)
for %%E in (ZSTD_versionNumber ZSTD_compress ZSTD_decompress ZSTD_createCStream ZSTD_createDStream) do (
    dumpbin /exports "!VERIFY_STAGE!\bin\libzstd.dll" | findstr /c:" %%E" >nul
    if errorlevel 1 (
        echo ERROR: Staged libzstd.dll does not export %%E.
        exit /b 1
    )
)

set "ZSTD_VERIFY_DLL=!VERIFY_STAGE!\bin\libzstd.dll"
"!WINDOWS_POWERSHELL!" -NoProfile -Command "$version=(Get-Item -LiteralPath $env:ZSTD_VERIFY_DLL).VersionInfo.FileVersion; if ($version -ne '1.5.7') { Write-Error ('Unexpected zstd DLL file version: ' + $version); exit 1 }"
if errorlevel 1 (
    echo ERROR: Staged libzstd.dll does not report file version !EXPECTED_ZSTD_VERSION!.
    exit /b 1
)

dumpbin /dependents "!VERIFY_STAGE!\bin\libzstd.dll" | findstr /i /c:"VCRUNTIME140D.dll" /c:"VCRUNTIME140_1D.dll" /c:"ucrtbased.dll" >nul
if /i "!VERIFY_CONFIG!"=="Release" (
    if not errorlevel 1 (
        echo ERROR: Release libzstd.dll unexpectedly depends on the Debug CRT.
        exit /b 1
    )
) else (
    if errorlevel 1 (
        echo ERROR: Debug libzstd.dll does not depend on the expected Debug CRT.
        exit /b 1
    )
)

dumpbin /dependents "!VERIFY_STAGE!\bin\libzstd.dll" | findstr /i /c:"zlib1.dll" /c:"liblzma.dll" /c:"liblz4.dll" /c:"lz4.dll" >nul
if not errorlevel 1 (
    echo ERROR: libzstd.dll unexpectedly depends on an optional compatibility backend.
    exit /b 1
)

if exist "!VERIFY_STAGE!\bin\libzstdd.dll" (
    echo ERROR: Debug-postfix DLL leaked into the stage: !VERIFY_STAGE!\bin\libzstdd.dll
    exit /b 1
)
if exist "!VERIFY_STAGE!\lib\libzstdd.lib" (
    echo ERROR: Debug-postfix import library leaked into the stage: !VERIFY_STAGE!\lib\libzstdd.lib
    exit /b 1
)
if exist "!VERIFY_STAGE!\lib\zstd_static.lib" (
    echo ERROR: Static zstd library leaked into the stage: !VERIFY_STAGE!\lib\zstd_static.lib
    exit /b 1
)
if exist "!VERIFY_STAGE!\bin\zstd.exe" (
    echo ERROR: zstd CLI leaked into the stage: !VERIFY_STAGE!\bin\zstd.exe
    exit /b 1
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
    echo ERROR: CMake 3.22 or newer is required. Found !CMAKE_VERSION!.
    exit /b 1
)
if !CMAKE_VERSION_MAJOR! EQU 3 if !CMAKE_VERSION_MINOR! LSS 22 (
    echo ERROR: CMake 3.22 or newer is required. Found !CMAKE_VERSION!.
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
    echo [zstd] Removing: !REMOVE_TARGET!
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

:show_help
echo SQLiteBrowser zstd 1.5.7 Windows x64 build script
echo.
echo Usage:
echo   third_party\zstd\build.cmd check
echo   third_party\zstd\build.cmd build [all^|debug^|release]
echo   third_party\zstd\build.cmd test [all^|debug^|release]
echo   third_party\zstd\build.cmd clean [all^|debug^|release]
echo   third_party\zstd\build.cmd [all^|debug^|release]
echo   third_party\zstd\build.cmd --help
echo.
echo Defaults:
echo   build all
echo.
echo Actions:
echo   build     Build only libzstd.dll, stage it, and verify product artifacts.
echo   test      Build the excluded smoke target, run it, and write test-manifest.txt.
echo   clean     Remove only the selected zstd private build directory.
echo   check     Validate source and toolchain without generating output.
echo.
echo Stage directories:
echo   output\x64-shared-debug\build\zstd\stage
echo   output\x64-shared-release\build\zstd\stage
echo.
echo The build action does not compile or run the project-owned smoke test.
echo Upstream static tests and optional zlib/LZMA/LZ4 compatibility are disabled.
exit /b 0

:show_help_error
call :show_help
exit /b 1
