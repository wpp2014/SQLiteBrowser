@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "PROJECT_ROOT=%%~fI"
for %%I in ("%SCRIPT_DIR%.") do set "BROTLI_CMAKE_DIR=%%~fI"

set "BROTLI_SRC=%SCRIPT_DIR%src"
set "OUTPUT_ROOT=%PROJECT_ROOT%\output"
set "EXPECTED_BROTLI_COMMIT=028fb5a23661f123017c060daa546b55cf4bde29"
set "EXPECTED_BROTLI_TAG=v1.2.0"
set "EXPECTED_BROTLI_VERSION=1.2.0"
set "REQUIRED_WINDOWS_SDK=10.0.26100.0"

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

echo [Brotli] Project root:  !PROJECT_ROOT!
echo [Brotli] Source:        !BROTLI_SRC!
echo [Brotli] Action:        !ACTION!
echo [Brotli] Configuration: !BUILD_CONFIG!
echo.

call :require_tool git.exe "Install Git and add git.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool cmake.exe "Install CMake 3.22 or newer and add cmake.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool ctest.exe "Install CMake with CTest and add ctest.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool certutil.exe "Windows certutil.exe is required to calculate artifact SHA-256 values."
if errorlevel 1 exit /b 1

call :check_cmake_version
if errorlevel 1 exit /b 1

if not exist "!BROTLI_SRC!\CMakeLists.txt" (
    if /i "!ACTION!"=="check" (
        echo ERROR: The Brotli submodule is not initialised: !BROTLI_SRC!
        echo Run: git submodule update --init --recursive
        exit /b 1
    )

    echo [Brotli] Initialising the Brotli submodule...
    git -C "!PROJECT_ROOT!" submodule update --init --recursive -- third_party/brotli/src
    if errorlevel 1 (
        echo ERROR: Failed to initialise the Brotli submodule.
        exit /b 1
    )
)

if not exist "!BROTLI_SRC!\CMakeLists.txt" (
    echo ERROR: Brotli CMakeLists.txt is missing after submodule initialisation.
    exit /b 1
)
if not exist "!BROTLI_SRC!\c\include\brotli\encode.h" (
    echo ERROR: Brotli encoder public header is missing after submodule initialisation.
    exit /b 1
)
if not exist "!BROTLI_SRC!\c\include\brotli\decode.h" (
    echo ERROR: Brotli decoder public header is missing after submodule initialisation.
    exit /b 1
)

set "BROTLI_COMMIT="
for /f "usebackq delims=" %%I in (`git -C "!BROTLI_SRC!" rev-parse HEAD 2^>nul`) do set "BROTLI_COMMIT=%%I"
if not defined BROTLI_COMMIT (
    echo ERROR: Unable to read the Brotli submodule commit.
    exit /b 1
)
if /i not "!BROTLI_COMMIT!"=="!EXPECTED_BROTLI_COMMIT!" (
    echo ERROR: Unexpected Brotli submodule commit.
    echo Expected: !EXPECTED_BROTLI_COMMIT! ^(!EXPECTED_BROTLI_TAG!^)
    echo Actual:   !BROTLI_COMMIT!
    echo Refusing to build an unverified Brotli revision.
    exit /b 1
)

set "BROTLI_TAG="
for /f "usebackq delims=" %%I in (`git -C "!BROTLI_SRC!" describe --tags --exact-match 2^>nul`) do set "BROTLI_TAG=%%I"
if /i not "!BROTLI_TAG!"=="!EXPECTED_BROTLI_TAG!" (
    echo ERROR: The Brotli submodule is not checked out at tag !EXPECTED_BROTLI_TAG!.
    echo Actual tag: !BROTLI_TAG!
    exit /b 1
)

set "BROTLI_DIRTY="
for /f "usebackq delims=" %%I in (`git -C "!BROTLI_SRC!" status --porcelain=v1 --untracked-files=all --ignore-submodules=all 2^>nul`) do set "BROTLI_DIRTY=1"
if defined BROTLI_DIRTY (
    echo ERROR: The Brotli source submodule has local changes.
    echo Commit, stash, or remove those changes before building.
    git -C "!BROTLI_SRC!" status --short --ignore-submodules=all
    exit /b 1
)

call :find_visual_studio
if errorlevel 1 exit /b 1

echo [Brotli] Visual Studio: !VS_EDITION! 2022
echo [Brotli] Initialising MSVC x64 with Windows SDK !REQUIRED_WINDOWS_SDK!...
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
echo [Brotli] Toolchain checks passed.
echo [Brotli] Brotli revision: !EXPECTED_BROTLI_TAG! / !BROTLI_COMMIT!
echo [Brotli] MSVC tools: !VCToolsVersion!
echo [Brotli] Windows SDK: !WINDOWS_SDK_ACTUAL!
echo [Brotli] CMake: !CMAKE_VERSION!

if /i "!ACTION!"=="check" (
    echo [Brotli] Environment check completed successfully. No build was performed.
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
echo [Brotli] Requested minimal product build completed successfully.
echo [Brotli] Output root: !OUTPUT_ROOT!
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
echo.
echo [Brotli] Requested tests completed successfully.
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
echo [Brotli] Requested clean completed successfully.
exit /b 0

:set_action
if "!ACTION_EXPLICIT!"=="1" (
    if /i not "!ACTION!"=="%~1" (
        echo ERROR: Multiple actions were specified: !ACTION! and %~1.
        exit /b 1
    )
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

set "CURRENT_CONFIG_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG_LOWER!"
set "CURRENT_ROOT=!CURRENT_CONFIG_ROOT!\build\brotli"
set "CURRENT_WORK=!CURRENT_ROOT!\work"
set "CURRENT_STAGE=!CURRENT_ROOT!\stage"

if not exist "!CURRENT_WORK!" mkdir "!CURRENT_WORK!"
if errorlevel 1 (
    echo ERROR: Failed to create Brotli work directory: !CURRENT_WORK!
    exit /b 1
)

set "VS_ROOT_CMAKE=!VS_ROOT:\=/!"
set "CURRENT_STAGE_CMAKE=!CURRENT_STAGE:\=/!"

echo.
echo ================================================================================
echo [Brotli] Configuring !CURRENT_CONFIG! x64
echo [Brotli] Work:  !CURRENT_WORK!
echo [Brotli] Stage: !CURRENT_STAGE!
echo ================================================================================

cmake -S "!BROTLI_CMAKE_DIR!" -B "!CURRENT_WORK!" ^
    -G "Visual Studio 17 2022" ^
    -A x64 ^
    "-DCMAKE_GENERATOR_INSTANCE=!VS_ROOT_CMAKE!" ^
    "-DCMAKE_SYSTEM_VERSION=!REQUIRED_WINDOWS_SDK!" ^
    "-DCMAKE_INSTALL_PREFIX=!CURRENT_STAGE_CMAKE!" ^
    "-DBROTLI_WINDOWS_SDK_VERSION=!REQUIRED_WINDOWS_SDK!"
if errorlevel 1 (
    echo ERROR: Brotli !CURRENT_CONFIG! CMake configuration failed.
    echo If this work directory used another generator or VS instance, rerun with clean.
    exit /b 1
)

echo.
echo [Brotli] Building !CURRENT_CONFIG! x64 product targets...
cmake --build "!CURRENT_WORK!" --config !CURRENT_CONFIG! --parallel --target brotlicommon brotlidec brotlienc
if errorlevel 1 (
    echo ERROR: Brotli !CURRENT_CONFIG! build failed.
    exit /b 1
)

call :remove_exact_directory "!CURRENT_STAGE!" "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1

echo.
echo [Brotli] Installing !CURRENT_CONFIG! stage...
cmake --install "!CURRENT_WORK!" --config !CURRENT_CONFIG! --prefix "!CURRENT_STAGE!"
if errorlevel 1 (
    echo ERROR: Brotli !CURRENT_CONFIG! stage installation failed.
    exit /b 1
)

call :write_manifest !CURRENT_CONFIG! !CURRENT_CONFIG_LOWER! "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1
call :verify_stage !CURRENT_CONFIG! !CURRENT_CONFIG_LOWER! "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1

echo [Brotli] !CURRENT_CONFIG! minimal build, stage, and verification completed.
exit /b 0

:test_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_CONFIG_LOWER=%~1"
if /i "!CURRENT_CONFIG!"=="Debug" set "CURRENT_CONFIG_LOWER=debug"
if /i "!CURRENT_CONFIG!"=="Release" set "CURRENT_CONFIG_LOWER=release"
set "CURRENT_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG_LOWER!\build\brotli"
set "CURRENT_WORK=!CURRENT_ROOT!\work"
set "CURRENT_STAGE=!CURRENT_ROOT!\stage"

if not exist "!CURRENT_WORK!\CMakeCache.txt" (
    echo ERROR: Brotli !CURRENT_CONFIG! has not been configured.
    echo Run: third_party\brotli\build.cmd build !CURRENT_CONFIG_LOWER!
    exit /b 1
)
call :verify_stage !CURRENT_CONFIG! !CURRENT_CONFIG_LOWER! "!CURRENT_STAGE!"
if errorlevel 1 (
    echo ERROR: Brotli !CURRENT_CONFIG! staged product is missing or invalid.
    echo Run: third_party\brotli\build.cmd build !CURRENT_CONFIG_LOWER!
    exit /b 1
)

echo.
echo [Brotli] Building !CURRENT_CONFIG! test-only target...
cmake --build "!CURRENT_WORK!" --config !CURRENT_CONFIG! --parallel --target brotli_shared_smoke
if errorlevel 1 (
    echo ERROR: Brotli !CURRENT_CONFIG! smoke target build failed.
    exit /b 1
)

echo [Brotli] Running !CURRENT_CONFIG! shared-library smoke test...
ctest --test-dir "!CURRENT_WORK!" -C !CURRENT_CONFIG! -R "^brotli\.shared\.smoke$" --output-on-failure
if errorlevel 1 (
    echo ERROR: Brotli !CURRENT_CONFIG! shared-library smoke test failed.
    exit /b 1
)

call :write_test_manifest !CURRENT_CONFIG! "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1
echo [Brotli] !CURRENT_CONFIG! test completed; product artifacts were not reinstalled.
exit /b 0

:clean_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_CONFIG_LOWER=%~1"
if /i "!CURRENT_CONFIG!"=="Debug" set "CURRENT_CONFIG_LOWER=debug"
if /i "!CURRENT_CONFIG!"=="Release" set "CURRENT_CONFIG_LOWER=release"
set "CURRENT_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG_LOWER!\build\brotli"
call :remove_exact_directory "!CURRENT_ROOT!" "!CURRENT_ROOT!"
exit /b !ERRORLEVEL!

:write_manifest
set "MANIFEST_CONFIG=%~1"
set "MANIFEST_STAGE=%~3"
set "MANIFEST_FILE=!MANIFEST_STAGE!\build-manifest.txt"
set "MANIFEST_CRT=/MD"
if /i "!MANIFEST_CONFIG!"=="Debug" set "MANIFEST_CRT=/MDd"

for %%L in (brotlicommon brotlidec brotlienc) do (
    call :calculate_sha256 "!MANIFEST_STAGE!\bin\%%L.dll" %%L_DLL_SHA256
    if errorlevel 1 exit /b 1
    call :calculate_sha256 "!MANIFEST_STAGE!\bin\%%L.pdb" %%L_PDB_SHA256
    if errorlevel 1 exit /b 1
    call :calculate_sha256 "!MANIFEST_STAGE!\lib\%%L.lib" %%L_LIB_SHA256
    if errorlevel 1 exit /b 1
)

>"!MANIFEST_FILE!" echo Brotli tag: !EXPECTED_BROTLI_TAG!
>>"!MANIFEST_FILE!" echo Brotli commit: !BROTLI_COMMIT!
>>"!MANIFEST_FILE!" echo Configuration: !MANIFEST_CONFIG!
>>"!MANIFEST_FILE!" echo Architecture: x64
>>"!MANIFEST_FILE!" echo Visual Studio: !VS_EDITION! 2022
>>"!MANIFEST_FILE!" echo MSVC tools: !VCToolsVersion!
>>"!MANIFEST_FILE!" echo Windows SDK: !WINDOWS_SDK_ACTUAL!
>>"!MANIFEST_FILE!" echo CMake: !CMAKE_VERSION!
>>"!MANIFEST_FILE!" echo CRT: !MANIFEST_CRT!
>>"!MANIFEST_FILE!" echo Library type: shared
>>"!MANIFEST_FILE!" echo DLLs: brotlicommon.dll; brotlidec.dll; brotlienc.dll
>>"!MANIFEST_FILE!" echo Linker PDBs: brotlicommon.pdb; brotlidec.pdb; brotlienc.pdb
>>"!MANIFEST_FILE!" echo PDB policy: linker PDBs staged; compiler PDBs excluded
>>"!MANIFEST_FILE!" echo Release symbol flags: /Zi /DEBUG:FULL /OPT:REF /OPT:ICF
>>"!MANIFEST_FILE!" echo Import libraries: brotlicommon.lib; brotlidec.lib; brotlienc.lib
>>"!MANIFEST_FILE!" echo Static package targets: OFF
>>"!MANIFEST_FILE!" echo Brotli CLI: OFF
>>"!MANIFEST_FILE!" echo BROTLI_BUNDLED_MODE: OFF
>>"!MANIFEST_FILE!" echo Project shared smoke test: not run
>>"!MANIFEST_FILE!" echo Upstream CLI tests: not run
>>"!MANIFEST_FILE!" echo Runtime version verification: not run
>>"!MANIFEST_FILE!" echo brotlicommon.dll SHA-256: !brotlicommon_DLL_SHA256!
>>"!MANIFEST_FILE!" echo brotlicommon.pdb SHA-256: !brotlicommon_PDB_SHA256!
>>"!MANIFEST_FILE!" echo brotlicommon.lib SHA-256: !brotlicommon_LIB_SHA256!
>>"!MANIFEST_FILE!" echo brotlidec.dll SHA-256: !brotlidec_DLL_SHA256!
>>"!MANIFEST_FILE!" echo brotlidec.pdb SHA-256: !brotlidec_PDB_SHA256!
>>"!MANIFEST_FILE!" echo brotlidec.lib SHA-256: !brotlidec_LIB_SHA256!
>>"!MANIFEST_FILE!" echo brotlienc.dll SHA-256: !brotlienc_DLL_SHA256!
>>"!MANIFEST_FILE!" echo brotlienc.pdb SHA-256: !brotlienc_PDB_SHA256!
>>"!MANIFEST_FILE!" echo brotlienc.lib SHA-256: !brotlienc_LIB_SHA256!
if errorlevel 1 (
    echo ERROR: Failed to write Brotli build manifest: !MANIFEST_FILE!
    exit /b 1
)
exit /b 0

:write_test_manifest
set "TEST_CONFIG=%~1"
set "TEST_STAGE=%~2"
set "TEST_BUILD_MANIFEST=!TEST_STAGE!\build-manifest.txt"
set "TEST_MANIFEST=!TEST_STAGE!\test-manifest.txt"
call :calculate_sha256 "!TEST_BUILD_MANIFEST!" BUILD_MANIFEST_SHA256
if errorlevel 1 exit /b 1

>"!TEST_MANIFEST!" echo Brotli tag: !EXPECTED_BROTLI_TAG!
>>"!TEST_MANIFEST!" echo Brotli commit: !BROTLI_COMMIT!
>>"!TEST_MANIFEST!" echo Configuration: !TEST_CONFIG!
>>"!TEST_MANIFEST!" echo Build manifest SHA-256: !BUILD_MANIFEST_SHA256!
>>"!TEST_MANIFEST!" echo Project shared smoke test: passed
>>"!TEST_MANIFEST!" echo Encoder runtime version: !EXPECTED_BROTLI_VERSION!
>>"!TEST_MANIFEST!" echo Decoder runtime version: !EXPECTED_BROTLI_VERSION!
>>"!TEST_MANIFEST!" echo Upstream CLI tests: not run
if errorlevel 1 (
    echo ERROR: Failed to write Brotli test manifest: !TEST_MANIFEST!
    exit /b 1
)
exit /b 0

:calculate_sha256
set "HASH_FILE=%~1"
set "HASH_RESULT_VARIABLE=%~2"
set "HASH_OUTPUT=%TEMP%\sqlitebrowser-brotli-hash-!RANDOM!-!RANDOM!.tmp"
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
set "VERIFY_STAGE=%~3"

for %%F in (
    "!VERIFY_STAGE!\bin\brotlicommon.dll"
    "!VERIFY_STAGE!\bin\brotlicommon.pdb"
    "!VERIFY_STAGE!\bin\brotlidec.dll"
    "!VERIFY_STAGE!\bin\brotlidec.pdb"
    "!VERIFY_STAGE!\bin\brotlienc.dll"
    "!VERIFY_STAGE!\bin\brotlienc.pdb"
    "!VERIFY_STAGE!\include\brotli\decode.h"
    "!VERIFY_STAGE!\include\brotli\encode.h"
    "!VERIFY_STAGE!\include\brotli\port.h"
    "!VERIFY_STAGE!\include\brotli\shared_dictionary.h"
    "!VERIFY_STAGE!\include\brotli\types.h"
    "!VERIFY_STAGE!\lib\brotlicommon.lib"
    "!VERIFY_STAGE!\lib\brotlidec.lib"
    "!VERIFY_STAGE!\lib\brotlienc.lib"
    "!VERIFY_STAGE!\lib\pkgconfig\libbrotlicommon.pc"
    "!VERIFY_STAGE!\lib\pkgconfig\libbrotlidec.pc"
    "!VERIFY_STAGE!\lib\pkgconfig\libbrotlienc.pc"
    "!VERIFY_STAGE!\share\licenses\brotli\LICENSE"
    "!VERIFY_STAGE!\build-manifest.txt"
) do (
    if not exist "%%~fF" (
        echo ERROR: Expected staged artifact is missing: %%~fF
        exit /b 1
    )
)

findstr /x /c:"Brotli tag: !EXPECTED_BROTLI_TAG!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: Brotli stage manifest has an unexpected tag.
    exit /b 1
)
findstr /x /c:"Brotli commit: !EXPECTED_BROTLI_COMMIT!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: Brotli stage manifest has an unexpected commit.
    exit /b 1
)
findstr /x /c:"Configuration: !VERIFY_CONFIG!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: Brotli stage manifest has an unexpected configuration.
    exit /b 1
)
findstr /x /c:"Windows SDK: !REQUIRED_WINDOWS_SDK!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: Brotli stage manifest has an unexpected Windows SDK.
    exit /b 1
)
findstr /x /c:"Project shared smoke test: not run" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: Brotli build manifest has an unexpected test status.
    exit /b 1
)

set /a VERIFY_DLL_COUNT=0
for %%F in ("!VERIFY_STAGE!\bin\*.dll") do if exist "%%~fF" set /a VERIFY_DLL_COUNT+=1
if not "!VERIFY_DLL_COUNT!"=="3" (
    echo ERROR: Brotli stage must contain exactly three DLLs; found !VERIFY_DLL_COUNT!.
    exit /b 1
)

set /a VERIFY_PDB_COUNT=0
for %%F in ("!VERIFY_STAGE!\bin\*.pdb") do if exist "%%~fF" set /a VERIFY_PDB_COUNT+=1
if not "!VERIFY_PDB_COUNT!"=="3" (
    echo ERROR: Brotli stage must contain exactly three linker PDBs; found !VERIFY_PDB_COUNT!.
    exit /b 1
)
set "VERIFY_COMPILER_PDB="
for /r "!VERIFY_STAGE!" %%F in (vc143.pdb) do if exist "%%~fF" set "VERIFY_COMPILER_PDB=%%~fF"
if defined VERIFY_COMPILER_PDB (
    echo ERROR: Compiler PDB vc143.pdb must not be deployed to the Brotli stage.
    echo Found: !VERIFY_COMPILER_PDB!
    exit /b 1
)

set /a VERIFY_LIB_COUNT=0
for %%F in ("!VERIFY_STAGE!\lib\*.lib") do if exist "%%~fF" set /a VERIFY_LIB_COUNT+=1
if not "!VERIFY_LIB_COUNT!"=="3" (
    echo ERROR: Brotli stage must contain exactly three import libraries; found !VERIFY_LIB_COUNT!.
    exit /b 1
)

for %%L in (brotlicommon brotlidec brotlienc) do (
    dumpbin /headers "!VERIFY_STAGE!\bin\%%L.dll" | findstr /i /c:"8664 machine (x64)" >nul
    if errorlevel 1 (
        echo ERROR: Staged %%L.dll is not an x64 DLL.
        exit /b 1
    )

    dumpbin /dependents "!VERIFY_STAGE!\bin\%%L.dll" | findstr /i /c:"VCRUNTIME140D.dll" /c:"VCRUNTIME140_1D.dll" /c:"ucrtbased.dll" >nul
    if /i "!VERIFY_CONFIG!"=="Release" (
        if not errorlevel 1 (
            echo ERROR: Release %%L.dll unexpectedly depends on the Debug CRT.
            exit /b 1
        )
    ) else (
        if errorlevel 1 (
            echo ERROR: Debug %%L.dll does not depend on the expected Debug CRT.
            exit /b 1
        )
    )

    dumpbin /dependents "!VERIFY_STAGE!\bin\%%L.dll" | findstr /i /c:"zlib" /c:"zstd" /c:"lzma" >nul
    if not errorlevel 1 (
        echo ERROR: %%L.dll unexpectedly depends on zlib, zstd, or LZMA.
        exit /b 1
    )
)

for %%L in (brotlidec brotlienc) do (
    dumpbin /dependents "!VERIFY_STAGE!\bin\%%L.dll" | findstr /i /c:"brotlicommon.dll" >nul
    if errorlevel 1 (
        echo ERROR: %%L.dll does not depend on brotlicommon.dll.
        exit /b 1
    )
)

for %%E in (BrotliEncoderCreateInstance BrotliEncoderCompressStream BrotliEncoderHasMoreOutput BrotliEncoderDestroyInstance BrotliEncoderCompress BrotliEncoderVersion) do (
    call :require_export "!VERIFY_STAGE!\bin\brotlienc.dll" %%E
    if errorlevel 1 exit /b 1
)
for %%E in (BrotliDecoderCreateInstance BrotliDecoderDecompressStream BrotliDecoderHasMoreOutput BrotliDecoderDestroyInstance BrotliDecoderGetErrorCode BrotliDecoderErrorString BrotliDecoderIsFinished BrotliDecoderDecompress BrotliDecoderVersion) do (
    call :require_export "!VERIFY_STAGE!\bin\brotlidec.dll" %%E
    if errorlevel 1 exit /b 1
)
call :require_export "!VERIFY_STAGE!\bin\brotlicommon.dll" BrotliGetDictionary
if errorlevel 1 exit /b 1

if exist "!VERIFY_STAGE!\bin\brotli.exe" (
    echo ERROR: Brotli CLI leaked into the stage.
    exit /b 1
)
for %%F in (
    "!VERIFY_STAGE!\bin\brotlicommond.dll"
    "!VERIFY_STAGE!\bin\brotlidecd.dll"
    "!VERIFY_STAGE!\bin\brotliencd.dll"
    "!VERIFY_STAGE!\lib\brotlicommond.lib"
    "!VERIFY_STAGE!\lib\brotlidecd.lib"
    "!VERIFY_STAGE!\lib\brotliencd.lib"
) do if exist "%%~fF" (
    echo ERROR: Debug-postfix artifact leaked into the stage: %%~fF
    exit /b 1
)
exit /b 0

:require_export
dumpbin /exports "%~1" | findstr /c:" %~2" >nul
if errorlevel 1 (
    echo ERROR: %~nx1 does not export %~2.
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
    echo [Brotli] Removing: !REMOVE_TARGET!
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
echo SQLiteBrowser Brotli 1.2.0 Windows x64 build script
echo.
echo Usage:
echo   third_party\brotli\build.cmd check
echo   third_party\brotli\build.cmd build [all^|debug^|release]
echo   third_party\brotli\build.cmd test [all^|debug^|release]
echo   third_party\brotli\build.cmd clean [all^|debug^|release]
echo   third_party\brotli\build.cmd [all^|debug^|release]
echo   third_party\brotli\build.cmd --help
echo.
echo Defaults:
echo   build all
echo.
echo Actions:
echo   build     Build only Brotli DLL product targets, stage, and verify them.
echo   test      Build the excluded smoke target, run it, and write test-manifest.txt.
echo   clean     Remove only the selected Brotli private build directory.
echo   check     Validate source and toolchain without generating output.
echo.
echo Stage directories:
echo   output\x64-shared-debug\build\brotli\stage
echo   output\x64-shared-release\build\brotli\stage
echo.
echo The build action does not compile or run the project-owned smoke test.
echo Upstream CLI tools, CLI tests, and static package targets are disabled.
exit /b 0

:show_help_error
call :show_help
exit /b 1
