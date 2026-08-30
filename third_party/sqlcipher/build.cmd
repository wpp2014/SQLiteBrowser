@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "PROJECT_ROOT=%%~fI"
for %%I in ("%SCRIPT_DIR%.") do set "SQLCIPHER_CMAKE_DIR=%%~fI"

set "SQLCIPHER_SRC=%SCRIPT_DIR%src"
set "OUTPUT_ROOT=%PROJECT_ROOT%\output"
set "EXPECTED_SQLCIPHER_COMMIT=63697beb0fafcb61faa7a3e6fd267036548ab11b"
set "EXPECTED_SQLCIPHER_TAG=v4.18.0"
set "EXPECTED_SQLITE_VERSION=3.53.4"
set "EXPECTED_OPENSSL_COMMIT=8cf17aaeb4599f8af87fefd810b5b5fee90fe69e"
set "EXPECTED_OPENSSL_TAG=openssl-3.5.7"
set "EXPECTED_BROTLI_COMMIT=028fb5a23661f123017c060daa546b55cf4bde29"
set "EXPECTED_BROTLI_TAG=v1.2.0"
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

echo [SQLCipher] Project root:  !PROJECT_ROOT!
echo [SQLCipher] Source:        !SQLCIPHER_SRC!
echo [SQLCipher] Action:        !ACTION!
echo [SQLCipher] Configuration: !BUILD_CONFIG!
echo.

if /i "!ACTION!"=="clean" goto dispatch_clean

call :require_tool git.exe "Install Git and add git.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool cmake.exe "Install CMake 3.22 or newer and add cmake.exe to PATH."
if errorlevel 1 exit /b 1
if /i "!ACTION!"=="test" (
    call :require_tool ctest.exe "Install CMake with CTest and add ctest.exe to PATH."
    if errorlevel 1 exit /b 1
)
if /i not "!ACTION!"=="check" (
    call :require_tool certutil.exe "Windows certutil.exe is required to calculate SHA-256 values."
    if errorlevel 1 exit /b 1
)
call :check_cmake_version
if errorlevel 1 exit /b 1

if not exist "!SQLCIPHER_SRC!\Makefile.msc" (
    if /i not "!ACTION!"=="build" (
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

for %%F in (
    "!SQLCIPHER_SRC!\Makefile.msc"
    "!SQLCIPHER_SRC!\src\sqlcipher.c"
    "!SQLCIPHER_SRC!\src\crypto_openssl.c"
    "!SQLCIPHER_SRC!\src\sqlite3.rc"
) do if not exist "%%~fF" (
    echo ERROR: SQLCipher source is incomplete: %%~fF
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
    exit /b 1
)

set "SQLCIPHER_TAG="
for /f "usebackq delims=" %%I in (`git -C "!SQLCIPHER_SRC!" describe --tags --exact-match 2^>nul`) do set "SQLCIPHER_TAG=%%I"
if /i not "!SQLCIPHER_TAG!"=="!EXPECTED_SQLCIPHER_TAG!" (
    echo ERROR: The SQLCipher submodule is not checked out at tag !EXPECTED_SQLCIPHER_TAG!.
    echo Actual tag: !SQLCIPHER_TAG!
    exit /b 1
)

set "SQLCIPHER_DIRTY="
for /f "usebackq delims=" %%I in (`git -C "!SQLCIPHER_SRC!" status --porcelain=v1 --untracked-files=all --ignore-submodules=all 2^>nul`) do set "SQLCIPHER_DIRTY=1"
if defined SQLCIPHER_DIRTY (
    echo ERROR: The SQLCipher source submodule has local changes.
    git -C "!SQLCIPHER_SRC!" status --short --ignore-submodules=all
    exit /b 1
)

set "SQLITE_VERSION="
set /p SQLITE_VERSION=<"!SQLCIPHER_SRC!\VERSION"
if not "!SQLITE_VERSION!"=="!EXPECTED_SQLITE_VERSION!" (
    echo ERROR: Unexpected SQLite baseline. Expected !EXPECTED_SQLITE_VERSION!, got !SQLITE_VERSION!.
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
if not defined VCToolsVersion (
    echo ERROR: Unable to determine the selected MSVC tools version.
    exit /b 1
)
set "WINDOWS_SDK_ACTUAL=!WindowsSDKVersion:\=!"

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
echo [SQLCipher] SQLite baseline: !SQLITE_VERSION!
echo [SQLCipher] MSVC tools: !VCToolsVersion!
echo [SQLCipher] Windows SDK: !WINDOWS_SDK_ACTUAL!
echo [SQLCipher] CMake: !CMAKE_VERSION!

if /i "!ACTION!"=="check" (
    echo [SQLCipher] Environment check completed successfully. No build was performed.
    exit /b 0
)

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
echo [SQLCipher] Requested minimal product build completed successfully.
echo [SQLCipher] Output root: !OUTPUT_ROOT!
echo [SQLCipher] Tests were not built or run. Use: third_party\sqlcipher\build.cmd test !BUILD_CONFIG!
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
echo [SQLCipher] Requested provider smoke tests completed successfully.
echo [SQLCipher] NOTE: The Tcl SQLCipher suite was not run.
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
echo [SQLCipher] Requested build directories were cleaned successfully.
exit /b 0

:build_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_CONFIG_LOWER=%~1"
if /i "!CURRENT_CONFIG!"=="Debug" set "CURRENT_CONFIG_LOWER=debug"
if /i "!CURRENT_CONFIG!"=="Release" set "CURRENT_CONFIG_LOWER=release"

set "CURRENT_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG_LOWER!\build\sqlcipher"
set "CURRENT_WORK=!CURRENT_ROOT!\work"
set "CURRENT_STAGE=!CURRENT_ROOT!\stage"
set "CURRENT_OPENSSL=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG_LOWER!\build\openssl\stage"
if not exist "!CURRENT_WORK!" mkdir "!CURRENT_WORK!"
if errorlevel 1 (
    echo ERROR: Failed to create SQLCipher work directory: !CURRENT_WORK!
    exit /b 1
)

set "VS_ROOT_CMAKE=!VS_ROOT:\=/!"
set "CURRENT_STAGE_CMAKE=!CURRENT_STAGE:\=/!"
set "CURRENT_OPENSSL_CMAKE=!CURRENT_OPENSSL:\=/!"

echo.
echo ================================================================================
echo [SQLCipher] Configuring !CURRENT_CONFIG! x64
echo [SQLCipher] Work:    !CURRENT_WORK!
echo [SQLCipher] Stage:   !CURRENT_STAGE!
echo [SQLCipher] OpenSSL: !CURRENT_OPENSSL!
echo ================================================================================

cmake -S "!SQLCIPHER_CMAKE_DIR!" -B "!CURRENT_WORK!" ^
    -G "Visual Studio 17 2022" ^
    -A x64 ^
    "-DCMAKE_GENERATOR_INSTANCE=!VS_ROOT_CMAKE!" ^
    "-DCMAKE_SYSTEM_VERSION=!REQUIRED_WINDOWS_SDK!" ^
    "-DCMAKE_INSTALL_PREFIX=!CURRENT_STAGE_CMAKE!" ^
    "-DSQLCIPHER_CONFIGURATION=!CURRENT_CONFIG!" ^
    "-DSQLCIPHER_WINDOWS_SDK_VERSION=!REQUIRED_WINDOWS_SDK!" ^
    "-DSQLCIPHER_OPENSSL_ROOT=!CURRENT_OPENSSL_CMAKE!"
if errorlevel 1 (
    echo ERROR: SQLCipher !CURRENT_CONFIG! CMake configuration failed.
    echo If this work directory used another generator or VS instance, rerun with clean.
    exit /b 1
)

echo.
echo [SQLCipher] Building !CURRENT_CONFIG! product target only...
cmake --build "!CURRENT_WORK!" --config !CURRENT_CONFIG! --parallel --target sqlcipher
if errorlevel 1 (
    echo ERROR: SQLCipher !CURRENT_CONFIG! build failed.
    exit /b 1
)

call :remove_exact_directory "!CURRENT_STAGE!" "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1

echo.
echo [SQLCipher] Installing !CURRENT_CONFIG! stage...
cmake --install "!CURRENT_WORK!" --config !CURRENT_CONFIG! --prefix "!CURRENT_STAGE!" --component SQLCipherProduct
if errorlevel 1 (
    echo ERROR: SQLCipher !CURRENT_CONFIG! stage installation failed.
    exit /b 1
)

call :write_manifest "!CURRENT_CONFIG!" "!CURRENT_STAGE!" "!CURRENT_OPENSSL!" "!CURRENT_WORK!"
if errorlevel 1 exit /b 1
call :verify_stage "!CURRENT_CONFIG!" "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1

echo [SQLCipher] !CURRENT_CONFIG! minimal product build, stage, and verification completed.
exit /b 0

:test_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_CONFIG_LOWER=%~1"
if /i "!CURRENT_CONFIG!"=="Debug" set "CURRENT_CONFIG_LOWER=debug"
if /i "!CURRENT_CONFIG!"=="Release" set "CURRENT_CONFIG_LOWER=release"
set "CURRENT_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG_LOWER!\build\sqlcipher"
set "CURRENT_WORK=!CURRENT_ROOT!\work"
set "CURRENT_STAGE=!CURRENT_ROOT!\stage"
set "CURRENT_OPENSSL=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG_LOWER!\build\openssl\stage"
set "CURRENT_TEST_RESULTS=!CURRENT_WORK!\test-results"
set "CURRENT_CLI=!CURRENT_WORK!\!CURRENT_CONFIG!\sqlcipher.exe"

if not exist "!CURRENT_WORK!\CMakeCache.txt" (
    echo ERROR: SQLCipher !CURRENT_CONFIG! has not been configured.
    echo Run: third_party\sqlcipher\build.cmd build !CURRENT_CONFIG_LOWER!
    exit /b 1
)
call :verify_stage "!CURRENT_CONFIG!" "!CURRENT_STAGE!"
if errorlevel 1 (
    echo ERROR: SQLCipher !CURRENT_CONFIG! product stage is missing or invalid.
    echo Run: third_party\sqlcipher\build.cmd build !CURRENT_CONFIG_LOWER!
    exit /b 1
)
if exist "!CURRENT_STAGE!\test-manifest.txt" del /q "!CURRENT_STAGE!\test-manifest.txt"
if exist "!CURRENT_STAGE!\test-manifest.txt" (
    echo ERROR: Failed to remove the stale SQLCipher test manifest.
    exit /b 1
)

echo.
echo [SQLCipher] Building !CURRENT_CONFIG! test-only CLI target...
cmake --build "!CURRENT_WORK!" --config !CURRENT_CONFIG! --parallel --target sqlcipher_cli
if errorlevel 1 (
    echo ERROR: SQLCipher !CURRENT_CONFIG! test-only CLI build failed.
    exit /b 1
)
if not exist "!CURRENT_CLI!" (
    echo ERROR: SQLCipher !CURRENT_CONFIG! test CLI is missing: !CURRENT_CLI!
    exit /b 1
)

echo [SQLCipher] Running !CURRENT_CONFIG! CTest provider smoke test...
ctest --test-dir "!CURRENT_WORK!" -C !CURRENT_CONFIG! --output-on-failure
if errorlevel 1 (
    echo ERROR: SQLCipher !CURRENT_CONFIG! CTest provider smoke test failed.
    exit /b 1
)

call :remove_exact_directory "!CURRENT_TEST_RESULTS!" "!CURRENT_TEST_RESULTS!"
if errorlevel 1 exit /b 1
mkdir "!CURRENT_TEST_RESULTS!"
if errorlevel 1 (
    echo ERROR: Failed to create SQLCipher test-results directory: !CURRENT_TEST_RESULTS!
    exit /b 1
)
copy /y "!CURRENT_CLI!" "!CURRENT_TEST_RESULTS!\sqlcipher-provider-smoke.exe" >nul
if errorlevel 1 (
    echo ERROR: Failed to prepare the staged-product provider smoke executable.
    exit /b 1
)

call :run_runtime_probes "!CURRENT_CONFIG!" "!CURRENT_TEST_RESULTS!\sqlcipher-provider-smoke.exe" "!CURRENT_TEST_RESULTS!" "!CURRENT_STAGE!" "!CURRENT_OPENSSL!"
if errorlevel 1 exit /b 1
call :write_test_manifest "!CURRENT_CONFIG!" "!CURRENT_STAGE!" "!CURRENT_TEST_RESULTS!"
if errorlevel 1 exit /b 1
call :verify_test_result "!CURRENT_CONFIG!" "!CURRENT_STAGE!" "!CURRENT_TEST_RESULTS!"
if errorlevel 1 exit /b 1
echo [SQLCipher] !CURRENT_CONFIG! provider smoke and staged-product probes completed.
exit /b 0

:clean_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_CONFIG_LOWER=%~1"
if /i "!CURRENT_CONFIG!"=="Debug" set "CURRENT_CONFIG_LOWER=debug"
if /i "!CURRENT_CONFIG!"=="Release" set "CURRENT_CONFIG_LOWER=release"
set "CURRENT_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG_LOWER!\build\sqlcipher"
call :remove_exact_directory "!CURRENT_ROOT!" "!CURRENT_ROOT!"
exit /b !ERRORLEVEL!

:run_runtime_probes
set "PROBE_CONFIG=%~1"
set "PROBE_CLI=%~2"
set "PROBE_RESULTS=%~3"
set "PROBE_STAGE=%~4"
set "PROBE_OPENSSL=%~5"
set "PROBE_OUTPUT=!PROBE_RESULTS!\provider-probe.txt"
set "COMPILE_OUTPUT=!PROBE_RESULTS!\compile-options.txt"
set "SAVED_PATH=!PATH!"
set "PATH=!PROBE_STAGE!\bin;!PROBE_OPENSSL!\bin;!PATH!"

"!PROBE_CLI!" :memory: "PRAGMA key='provider-probe'; PRAGMA cipher_version; PRAGMA cipher_provider; PRAGMA cipher_provider_version;" >"!PROBE_OUTPUT!" 2>&1
if errorlevel 1 (
    set "PATH=!SAVED_PATH!"
    echo ERROR: Staged SQLCipher provider probe failed.
    type "!PROBE_OUTPUT!"
    exit /b 1
)
findstr /i /c:"4.18.0 community" /c:"openssl" /c:"OpenSSL 3.5.7" "!PROBE_OUTPUT!" >nul
if errorlevel 1 (
    set "PATH=!SAVED_PATH!"
    echo ERROR: SQLCipher provider probe returned unexpected output.
    type "!PROBE_OUTPUT!"
    exit /b 1
)

"!PROBE_CLI!" :memory: "PRAGMA key='compile-probe'; PRAGMA compile_options;" >"!COMPILE_OUTPUT!" 2>&1
set "PATH=!SAVED_PATH!"
if errorlevel 1 (
    echo ERROR: SQLCipher compile-options probe failed.
    type "!COMPILE_OUTPUT!"
    exit /b 1
)
for %%O in (
    "ENABLE_BYTECODE_VTAB"
    "ENABLE_CARRAY"
    "ENABLE_COLUMN_METADATA"
    "ENABLE_DBPAGE_VTAB"
    "ENABLE_DBSTAT_VTAB"
    "ENABLE_FTS3"
    "ENABLE_FTS3_PARENTHESIS"
    "ENABLE_FTS5"
    "ENABLE_GEOPOLY"
    "ENABLE_MATH_FUNCTIONS"
    "ENABLE_PERCENTILE"
    "ENABLE_RTREE"
    "ENABLE_STAT4"
    "ENABLE_STMTVTAB"
    "EXTRA_INIT=sqlcipher_extra_init"
    "EXTRA_SHUTDOWN=sqlcipher_extra_shutdown"
    "HAS_CODEC"
    "MAX_ATTACHED=125"
    "SOUNDEX"
    "TEMP_STORE=2"
    "THREADSAFE=1"
) do (
    findstr /x /c:"%%~O" "!COMPILE_OUTPUT!" >nul
    if errorlevel 1 (
        echo ERROR: Required SQLCipher compile option is missing: %%~O
        exit /b 1
    )
)
exit /b 0

:write_manifest
set "MANIFEST_CONFIG=%~1"
set "MANIFEST_STAGE=%~2"
set "MANIFEST_OPENSSL=%~3"
set "MANIFEST_WORK=%~4"
set "MANIFEST_FILE=!MANIFEST_STAGE!\build-manifest.txt"
set "MANIFEST_CRT=/MD"
if /i "!MANIFEST_CONFIG!"=="Debug" set "MANIFEST_CRT=/MDd"

call :calculate_sha256 "!MANIFEST_STAGE!\bin\sqlcipher.dll" SQLCIPHER_DLL_SHA256
if errorlevel 1 exit /b 1
call :calculate_sha256 "!MANIFEST_STAGE!\lib\sqlcipher.lib" SQLCIPHER_LIB_SHA256
if errorlevel 1 exit /b 1
call :calculate_sha256 "!MANIFEST_OPENSSL!\build-manifest.txt" OPENSSL_MANIFEST_SHA256
if errorlevel 1 exit /b 1

>"!MANIFEST_FILE!" echo SQLCipher tag: !EXPECTED_SQLCIPHER_TAG!
>>"!MANIFEST_FILE!" echo SQLCipher commit: !SQLCIPHER_COMMIT!
>>"!MANIFEST_FILE!" echo SQLite baseline: !SQLITE_VERSION!
>>"!MANIFEST_FILE!" echo Configuration: !MANIFEST_CONFIG!
>>"!MANIFEST_FILE!" echo Architecture: x64
>>"!MANIFEST_FILE!" echo Visual Studio: !VS_EDITION! 2022
>>"!MANIFEST_FILE!" echo MSVC tools: !VCToolsVersion!
>>"!MANIFEST_FILE!" echo Windows SDK: !WINDOWS_SDK_ACTUAL!
>>"!MANIFEST_FILE!" echo CMake: !CMAKE_VERSION!
>>"!MANIFEST_FILE!" echo CRT: !MANIFEST_CRT!
>>"!MANIFEST_FILE!" echo Library type: shared
>>"!MANIFEST_FILE!" echo OpenSSL tag: !EXPECTED_OPENSSL_TAG!
>>"!MANIFEST_FILE!" echo OpenSSL commit: !EXPECTED_OPENSSL_COMMIT!
>>"!MANIFEST_FILE!" echo OpenSSL stage: !MANIFEST_OPENSSL!
>>"!MANIFEST_FILE!" echo OpenSSL manifest SHA-256: !OPENSSL_MANIFEST_SHA256!
>>"!MANIFEST_FILE!" echo Brotli tag: !EXPECTED_BROTLI_TAG!
>>"!MANIFEST_FILE!" echo Brotli commit: !EXPECTED_BROTLI_COMMIT!
>>"!MANIFEST_FILE!" echo Brotli contract: dynamically loaded by the matching OpenSSL stage
>>"!MANIFEST_FILE!" echo Product target: sqlcipher
>>"!MANIFEST_FILE!" echo Test-only target: sqlcipher_cli ^(excluded from default build^)
>>"!MANIFEST_FILE!" echo CTest provider smoke: not run
>>"!MANIFEST_FILE!" echo Product runtime probes: not run
>>"!MANIFEST_FILE!" echo Tcl SQLCipher test suite: not run
>>"!MANIFEST_FILE!" echo Linker PDBs: bin/sqlcipher.pdb
>>"!MANIFEST_FILE!" echo PDB policy: linker PDBs staged beside runtime binaries; generator and compiler PDBs excluded
>>"!MANIFEST_FILE!" echo sqlcipher.dll SHA-256: !SQLCIPHER_DLL_SHA256!
>>"!MANIFEST_FILE!" echo sqlcipher.lib SHA-256: !SQLCIPHER_LIB_SHA256!
for /f "usebackq delims=" %%L in ("!MANIFEST_WORK!\sqlcipher-build-settings.txt") do >>"!MANIFEST_FILE!" echo %%L
exit /b 0

:verify_stage
set "VERIFY_CONFIG=%~1"
set "VERIFY_STAGE=%~2"

for %%F in (
    "!VERIFY_STAGE!\bin\sqlcipher.dll"
    "!VERIFY_STAGE!\include\sqlcipher\sqlite3.h"
    "!VERIFY_STAGE!\include\sqlcipher\sqlite3ext.h"
    "!VERIFY_STAGE!\include\sqlcipher\sqlite3session.h"
    "!VERIFY_STAGE!\lib\sqlcipher.lib"
    "!VERIFY_STAGE!\bin\sqlcipher.pdb"
    "!VERIFY_STAGE!\share\licenses\sqlcipher\LICENSE.md"
    "!VERIFY_STAGE!\share\licenses\sqlcipher\SQLITE_LICENSE.md"
    "!VERIFY_STAGE!\build-manifest.txt"
) do if not exist "%%~fF" (
    echo ERROR: Expected staged artifact is missing: %%~fF
    exit /b 1
)

findstr /x /c:"SQLCipher tag: !EXPECTED_SQLCIPHER_TAG!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 exit /b 1
findstr /x /c:"SQLCipher commit: !EXPECTED_SQLCIPHER_COMMIT!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 exit /b 1
findstr /x /c:"Configuration: !VERIFY_CONFIG!" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 exit /b 1
findstr /x /c:"Build system: CMake/MSBuild (Makefile.msc source generation only)" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 exit /b 1
findstr /x /c:"CTest provider smoke: not run" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 exit /b 1

dumpbin /headers "!VERIFY_STAGE!\bin\sqlcipher.dll" | findstr /i /c:"8664 machine (x64)" >nul
if errorlevel 1 (
    echo ERROR: Staged sqlcipher.dll is not x64.
    exit /b 1
)
dumpbin /dependents "!VERIFY_STAGE!\bin\sqlcipher.dll" | findstr /i /c:"libcrypto-3-x64.dll" >nul
if errorlevel 1 (
    echo ERROR: sqlcipher.dll does not depend on libcrypto-3-x64.dll.
    exit /b 1
)
dumpbin /dependents "!VERIFY_STAGE!\bin\sqlcipher.dll" | findstr /i /c:"VCRUNTIME140D.dll" /c:"VCRUNTIME140_1D.dll" /c:"ucrtbased.dll" >nul
if /i "!VERIFY_CONFIG!"=="Release" (
    if not errorlevel 1 (
        echo ERROR: Release SQLCipher depends on the Debug CRT.
        exit /b 1
    )
) else (
    if errorlevel 1 (
        echo ERROR: Debug SQLCipher does not depend on the Debug CRT.
        exit /b 1
    )
)

for %%E in (sqlite3_open sqlite3_key sqlite3_rekey sqlcipher_version) do (
    dumpbin /exports "!VERIFY_STAGE!\bin\sqlcipher.dll" | findstr /c:" %%E" >nul
    if errorlevel 1 (
        echo ERROR: sqlcipher.dll does not export %%E.
        exit /b 1
    )
)

for %%F in (libcrypto-3-x64.dll libssl-3-x64.dll brotlicommon.dll brotlidec.dll brotlienc.dll) do if exist "!VERIFY_STAGE!\bin\%%F" (
    echo ERROR: Dependency runtime leaked into the SQLCipher-only stage: %%F
    exit /b 1
)
for %%F in (sqlcipher.exe sqlcipher-cli.pdb provider-probe.txt compile-options.txt) do if exist "!VERIFY_STAGE!\%%F" (
    echo ERROR: Test-only artifact leaked into the SQLCipher product stage: %%F
    exit /b 1
)
if exist "!VERIFY_STAGE!\bin\sqlcipher.exe" (
    echo ERROR: Test-only SQLCipher CLI leaked into the product stage.
    exit /b 1
)
if exist "!VERIFY_STAGE!\bin\sqlcipher-cli.pdb" (
    echo ERROR: Test-only SQLCipher CLI PDB leaked into the product stage.
    exit /b 1
)
for %%P in (vc140.pdb vc143.pdb lemon.pdb mkkeywordhash.pdb mksourceid.pdb src-verify.pdb) do (
    dir /s /b "!VERIFY_STAGE!\%%P" >nul 2>&1
    if not errorlevel 1 (
        echo ERROR: Generator or compiler PDB leaked into the SQLCipher stage: %%P
        exit /b 1
    )
)
exit /b 0

:write_test_manifest
set "TEST_CONFIG=%~1"
set "TEST_STAGE=%~2"
set "TEST_RESULTS=%~3"
set "TEST_MANIFEST=!TEST_STAGE!\test-manifest.txt"
call :calculate_sha256 "!TEST_STAGE!\build-manifest.txt" BUILD_MANIFEST_SHA256
if errorlevel 1 exit /b 1
call :calculate_sha256 "!TEST_RESULTS!\provider-probe.txt" PROVIDER_PROBE_SHA256
if errorlevel 1 exit /b 1
call :calculate_sha256 "!TEST_RESULTS!\compile-options.txt" COMPILE_OPTIONS_SHA256
if errorlevel 1 exit /b 1

>"!TEST_MANIFEST!" echo SQLCipher tag: !EXPECTED_SQLCIPHER_TAG!
>>"!TEST_MANIFEST!" echo SQLCipher commit: !SQLCIPHER_COMMIT!
>>"!TEST_MANIFEST!" echo Configuration: !TEST_CONFIG!
>>"!TEST_MANIFEST!" echo Build manifest SHA-256: !BUILD_MANIFEST_SHA256!
>>"!TEST_MANIFEST!" echo Test-only target: sqlcipher_cli
>>"!TEST_MANIFEST!" echo CTest provider smoke: passed
>>"!TEST_MANIFEST!" echo Staged-product provider probe: passed
>>"!TEST_MANIFEST!" echo Staged-product compile-options probe: passed
>>"!TEST_MANIFEST!" echo Tcl SQLCipher test suite: not run
>>"!TEST_MANIFEST!" echo Test results directory: !TEST_RESULTS!
>>"!TEST_MANIFEST!" echo provider-probe.txt SHA-256: !PROVIDER_PROBE_SHA256!
>>"!TEST_MANIFEST!" echo compile-options.txt SHA-256: !COMPILE_OPTIONS_SHA256!
if errorlevel 1 exit /b 1
exit /b 0

:verify_test_result
set "VERIFY_TEST_CONFIG=%~1"
set "VERIFY_TEST_STAGE=%~2"
set "VERIFY_TEST_RESULTS=%~3"
for %%F in (
    "!VERIFY_TEST_STAGE!\test-manifest.txt"
    "!VERIFY_TEST_RESULTS!\sqlcipher-provider-smoke.exe"
    "!VERIFY_TEST_RESULTS!\provider-probe.txt"
    "!VERIFY_TEST_RESULTS!\compile-options.txt"
) do if not exist "%%~fF" (
    echo ERROR: Expected SQLCipher test artifact is missing: %%~fF
    exit /b 1
)
call :calculate_sha256 "!VERIFY_TEST_STAGE!\build-manifest.txt" CURRENT_BUILD_MANIFEST_SHA256
if errorlevel 1 exit /b 1
findstr /x /c:"Configuration: !VERIFY_TEST_CONFIG!" "!VERIFY_TEST_STAGE!\test-manifest.txt" >nul
if errorlevel 1 exit /b 1
findstr /x /c:"Build manifest SHA-256: !CURRENT_BUILD_MANIFEST_SHA256!" "!VERIFY_TEST_STAGE!\test-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: SQLCipher test manifest does not match the current product build manifest.
    exit /b 1
)
findstr /x /c:"CTest provider smoke: passed" "!VERIFY_TEST_STAGE!\test-manifest.txt" >nul
if errorlevel 1 exit /b 1
findstr /x /c:"Staged-product provider probe: passed" "!VERIFY_TEST_STAGE!\test-manifest.txt" >nul
if errorlevel 1 exit /b 1
exit /b 0

:check_openssl
set "OPENSSL_CONFIG=%~1"
set "OPENSSL_STAGE=!OUTPUT_ROOT!\x64-shared-!OPENSSL_CONFIG!\build\openssl\stage"
set "OPENSSL_MANIFEST=!OPENSSL_STAGE!\build-manifest.txt"

for %%F in (
    "!OPENSSL_STAGE!\bin\libcrypto-3-x64.dll"
    "!OPENSSL_STAGE!\bin\brotlicommon.dll"
    "!OPENSSL_STAGE!\bin\brotlidec.dll"
    "!OPENSSL_STAGE!\bin\brotlienc.dll"
    "!OPENSSL_STAGE!\include\openssl\opensslv.h"
    "!OPENSSL_STAGE!\lib\libcrypto.lib"
    "!OPENSSL_MANIFEST!"
) do if not exist "%%~fF" (
    echo ERROR: Required !OPENSSL_CONFIG! OpenSSL artifact is missing: %%~fF
    echo Build it first with: third_party\openssl\build.cmd build !OPENSSL_CONFIG!
    exit /b 1
)

findstr /x /c:"OpenSSL tag: !EXPECTED_OPENSSL_TAG!" "!OPENSSL_MANIFEST!" >nul
if errorlevel 1 exit /b 1
findstr /x /c:"OpenSSL commit: !EXPECTED_OPENSSL_COMMIT!" "!OPENSSL_MANIFEST!" >nul
if errorlevel 1 exit /b 1
findstr /x /c:"Configuration: !OPENSSL_CONFIG!" "!OPENSSL_MANIFEST!" >nul
if errorlevel 1 exit /b 1
findstr /b /c:"Windows SDK: !REQUIRED_WINDOWS_SDK!" "!OPENSSL_MANIFEST!" >nul
if errorlevel 1 exit /b 1
findstr /x /c:"Brotli tag: !EXPECTED_BROTLI_TAG!" "!OPENSSL_MANIFEST!" >nul
if errorlevel 1 exit /b 1
findstr /x /c:"Brotli commit: !EXPECTED_BROTLI_COMMIT!" "!OPENSSL_MANIFEST!" >nul
if errorlevel 1 exit /b 1
findstr /i /c:"enable-brotli-dynamic" "!OPENSSL_MANIFEST!" >nul
if errorlevel 1 (
    echo ERROR: OpenSSL !OPENSSL_CONFIG! manifest does not record dynamic Brotli support.
    exit /b 1
)

dumpbin /dependents "!OPENSSL_STAGE!\bin\libcrypto-3-x64.dll" | findstr /i /c:"VCRUNTIME140D.dll" /c:"VCRUNTIME140_1D.dll" /c:"ucrtbased.dll" >nul
if /i "!OPENSSL_CONFIG!"=="release" (
    if not errorlevel 1 (
        echo ERROR: Release OpenSSL depends on the Debug CRT.
        exit /b 1
    )
) else (
    if errorlevel 1 (
        echo ERROR: Debug OpenSSL does not depend on the Debug CRT.
        exit /b 1
    )
)
exit /b 0

:calculate_sha256
set "HASH_FILE=%~1"
set "HASH_RESULT_VARIABLE=%~2"
set "HASH_OUTPUT=%TEMP%\sqlitebrowser-sqlcipher-hash-!RANDOM!-!RANDOM!.tmp"
set "HASH_VALUE="
if not exist "!HASH_FILE!" (
    echo ERROR: Cannot hash missing file: !HASH_FILE!
    exit /b 1
)
certutil.exe -hashfile "!HASH_FILE!" SHA256 >"!HASH_OUTPUT!" 2>nul
if errorlevel 1 (
    if exist "!HASH_OUTPUT!" del /q "!HASH_OUTPUT!"
    echo ERROR: certutil.exe failed to hash: !HASH_FILE!
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
    if not defined VS_ROOT if exist "C:\Program Files\Microsoft Visual Studio\2022\%%E\Common7\Tools\VsDevCmd.bat" (
        set "VS_ROOT=C:\Program Files\Microsoft Visual Studio\2022\%%E"
        set "VS_EDITION=%%E"
    )
)
if not defined VS_ROOT (
    echo ERROR: Visual Studio 2022 was not found in a supported default directory.
    echo Checked Enterprise, Professional, and Community under C:\Program Files.
    exit /b 1
)
set "VS_DEVCMD=!VS_ROOT!\Common7\Tools\VsDevCmd.bat"
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

:show_help
echo SQLiteBrowser SQLCipher 4.18.0 Windows x64 build script
echo.
echo Usage:
echo   third_party\sqlcipher\build.cmd [build^|test^|clean^|check] [all^|debug^|release]
echo   third_party\sqlcipher\build.cmd [all^|debug^|release]
echo   third_party\sqlcipher\build.cmd --help
echo.
echo Defaults:
echo   build all
echo.
echo Actions:
echo   build     Build only sqlcipher.dll, install the product stage, and verify it.
echo   test      Build the test-only CLI, run CTest and staged-product probes.
echo   clean     Remove only the selected SQLCipher private build directory.
echo   check     Validate source, toolchain, and matching OpenSSL/Brotli stage only.
echo.
echo Configuration:
echo   all       Select Debug and Release.
echo   debug     Select Debug only.
echo   release   Select Release only.
echo.
echo Build model:
echo   Makefile.msc generates the amalgamation and public sources only.
echo   build compiles and stages sqlcipher.dll only.
echo   test compiles sqlcipher.exe only as a private provider-smoke tool.
echo.
echo Stage directories:
echo   output\x64-shared-debug\build\sqlcipher\stage
echo   output\x64-shared-release\build\sqlcipher\stage
echo.
echo Test result directories:
echo   output\x64-shared-debug\build\sqlcipher\work\test-results
echo   output\x64-shared-release\build\sqlcipher\work\test-results
echo.
echo build-manifest.txt always records tests as not run. test-manifest.txt binds
echo successful provider smoke results to the current build manifest. The Tcl
echo SQLCipher suite is not run by this script.
exit /b 0

:show_help_error
call :show_help
exit /b 1
