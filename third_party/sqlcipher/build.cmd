@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "PROJECT_ROOT=%%~fI"
for %%I in ("%SCRIPT_DIR%.") do set "SQLCIPHER_CMAKE_DIR=%%~fI"

set "SQLCIPHER_SRC=%SCRIPT_DIR%src"
set "SQLCIPHER_BUILD_ROOT=%PROJECT_ROOT%\build\sqlcipher"
set "OPENSSL_BUILD_ROOT=%PROJECT_ROOT%\build\openssl"
set "EXPECTED_SQLCIPHER_COMMIT=63697beb0fafcb61faa7a3e6fd267036548ab11b"
set "EXPECTED_SQLCIPHER_TAG=v4.18.0"
set "EXPECTED_SQLITE_VERSION=3.53.4"
set "EXPECTED_OPENSSL_COMMIT=8cf17aaeb4599f8af87fefd810b5b5fee90fe69e"
set "EXPECTED_OPENSSL_TAG=openssl-3.5.7"
set "EXPECTED_BROTLI_COMMIT=028fb5a23661f123017c060daa546b55cf4bde29"
set "EXPECTED_BROTLI_TAG=v1.2.0"
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

call :require_tool git.exe "Install Git and add git.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool cmake.exe "Install CMake 3.22 or newer and add cmake.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool ctest.exe "Install CMake with CTest and add ctest.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool certutil.exe "Windows certutil.exe is required to calculate SHA-256 values."
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

if "!CHECK_ONLY!"=="1" (
    echo [SQLCipher] Environment check completed successfully. No build was performed.
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
echo [SQLCipher] Requested build completed successfully.
echo [SQLCipher] Build root: !SQLCIPHER_BUILD_ROOT!
echo [SQLCipher] NOTE: CTest and product smoke checks passed; the Tcl SQLCipher suite was not run.
exit /b 0

:build_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_CONFIG_LOWER=%~1"
if /i "!CURRENT_CONFIG!"=="Debug" set "CURRENT_CONFIG_LOWER=debug"
if /i "!CURRENT_CONFIG!"=="Release" set "CURRENT_CONFIG_LOWER=release"

set "CURRENT_ROOT=!SQLCIPHER_BUILD_ROOT!\x64-!CURRENT_CONFIG_LOWER!"
set "CURRENT_WORK=!CURRENT_ROOT!\work"
set "CURRENT_STAGE=!CURRENT_ROOT!\stage"
set "CURRENT_OPENSSL=!OPENSSL_BUILD_ROOT!\x64-!CURRENT_CONFIG_LOWER!\stage"

if "!CLEAN_BUILD!"=="1" (
    call :remove_exact_directory "!CURRENT_ROOT!" "!CURRENT_ROOT!"
    if errorlevel 1 exit /b 1
)
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
echo [SQLCipher] Building !CURRENT_CONFIG! with CMake/MSBuild...
cmake --build "!CURRENT_WORK!" --config !CURRENT_CONFIG! --parallel
if errorlevel 1 (
    echo ERROR: SQLCipher !CURRENT_CONFIG! build failed.
    exit /b 1
)

echo.
echo [SQLCipher] Running !CURRENT_CONFIG! CTest provider smoke test...
ctest --test-dir "!CURRENT_WORK!" -C !CURRENT_CONFIG! --output-on-failure
if errorlevel 1 (
    echo ERROR: SQLCipher !CURRENT_CONFIG! CTest provider smoke test failed.
    exit /b 1
)

call :remove_exact_directory "!CURRENT_STAGE!" "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1

echo.
echo [SQLCipher] Installing !CURRENT_CONFIG! stage...
cmake --install "!CURRENT_WORK!" --config !CURRENT_CONFIG! --prefix "!CURRENT_STAGE!"
if errorlevel 1 (
    echo ERROR: SQLCipher !CURRENT_CONFIG! stage installation failed.
    exit /b 1
)

call :run_runtime_probes "!CURRENT_CONFIG!" "!CURRENT_STAGE!" "!CURRENT_OPENSSL!"
if errorlevel 1 exit /b 1
call :write_manifest "!CURRENT_CONFIG!" "!CURRENT_STAGE!" "!CURRENT_OPENSSL!" "!CURRENT_WORK!"
if errorlevel 1 exit /b 1
call :verify_stage "!CURRENT_CONFIG!" "!CURRENT_STAGE!"
if errorlevel 1 exit /b 1

echo [SQLCipher] !CURRENT_CONFIG! build, CTest, stage, and verification completed.
exit /b 0

:run_runtime_probes
set "PROBE_CONFIG=%~1"
set "PROBE_STAGE=%~2"
set "PROBE_OPENSSL=%~3"
set "PROBE_OUTPUT=!PROBE_STAGE!\provider-probe.txt"
set "COMPILE_OUTPUT=!PROBE_STAGE!\compile-options.txt"
set "SAVED_PATH=!PATH!"
set "PATH=!PROBE_STAGE!\bin;!PROBE_OPENSSL!\bin;!PATH!"

"!PROBE_STAGE!\bin\sqlcipher.exe" :memory: "PRAGMA key='provider-probe'; PRAGMA cipher_version; PRAGMA cipher_provider; PRAGMA cipher_provider_version;" >"!PROBE_OUTPUT!" 2>&1
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

"!PROBE_STAGE!\bin\sqlcipher.exe" :memory: "PRAGMA key='compile-probe'; PRAGMA compile_options;" >"!COMPILE_OUTPUT!" 2>&1
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
call :calculate_sha256 "!MANIFEST_STAGE!\bin\sqlcipher.exe" SQLCIPHER_EXE_SHA256
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
>>"!MANIFEST_FILE!" echo CTest provider smoke: passed
>>"!MANIFEST_FILE!" echo Product runtime probes: passed
>>"!MANIFEST_FILE!" echo Tcl SQLCipher test suite: not run
>>"!MANIFEST_FILE!" echo Linker PDBs: bin/sqlcipher.pdb;bin/sqlcipher-cli.pdb
>>"!MANIFEST_FILE!" echo PDB policy: linker PDBs staged beside runtime binaries; generator and compiler PDBs excluded
>>"!MANIFEST_FILE!" echo sqlcipher.dll SHA-256: !SQLCIPHER_DLL_SHA256!
>>"!MANIFEST_FILE!" echo sqlcipher.exe SHA-256: !SQLCIPHER_EXE_SHA256!
>>"!MANIFEST_FILE!" echo sqlcipher.lib SHA-256: !SQLCIPHER_LIB_SHA256!
for /f "usebackq delims=" %%L in ("!MANIFEST_WORK!\sqlcipher-build-settings.txt") do >>"!MANIFEST_FILE!" echo %%L
exit /b 0

:verify_stage
set "VERIFY_CONFIG=%~1"
set "VERIFY_STAGE=%~2"

for %%F in (
    "!VERIFY_STAGE!\bin\sqlcipher.dll"
    "!VERIFY_STAGE!\bin\sqlcipher.exe"
    "!VERIFY_STAGE!\include\sqlcipher\sqlite3.h"
    "!VERIFY_STAGE!\include\sqlcipher\sqlite3ext.h"
    "!VERIFY_STAGE!\include\sqlcipher\sqlite3session.h"
    "!VERIFY_STAGE!\lib\sqlcipher.lib"
    "!VERIFY_STAGE!\bin\sqlcipher.pdb"
    "!VERIFY_STAGE!\bin\sqlcipher-cli.pdb"
    "!VERIFY_STAGE!\share\licenses\sqlcipher\LICENSE.md"
    "!VERIFY_STAGE!\share\licenses\sqlcipher\SQLITE_LICENSE.md"
    "!VERIFY_STAGE!\provider-probe.txt"
    "!VERIFY_STAGE!\compile-options.txt"
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
dumpbin /dependents "!VERIFY_STAGE!\bin\sqlcipher.exe" | findstr /i /c:"sqlcipher.dll" >nul
if errorlevel 1 (
    echo ERROR: sqlcipher.exe is not dynamically linked to sqlcipher.dll.
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
for %%P in (vc140.pdb vc143.pdb lemon.pdb mkkeywordhash.pdb mksourceid.pdb src-verify.pdb) do (
    dir /s /b "!VERIFY_STAGE!\%%P" >nul 2>&1
    if not errorlevel 1 (
        echo ERROR: Generator or compiler PDB leaked into the SQLCipher stage: %%P
        exit /b 1
    )
)
exit /b 0

:check_openssl
set "OPENSSL_CONFIG=%~1"
set "OPENSSL_STAGE=!OPENSSL_BUILD_ROOT!\x64-!OPENSSL_CONFIG!\stage"
set "OPENSSL_MANIFEST=!OPENSSL_STAGE!\build-manifest.txt"

for %%F in (
    "!OPENSSL_STAGE!\bin\openssl.exe"
    "!OPENSSL_STAGE!\bin\libcrypto-3-x64.dll"
    "!OPENSSL_STAGE!\bin\brotlicommon.dll"
    "!OPENSSL_STAGE!\bin\brotlidec.dll"
    "!OPENSSL_STAGE!\bin\brotlienc.dll"
    "!OPENSSL_STAGE!\include\openssl\opensslv.h"
    "!OPENSSL_STAGE!\lib\libcrypto.lib"
    "!OPENSSL_MANIFEST!"
) do if not exist "%%~fF" (
    echo ERROR: Required !OPENSSL_CONFIG! OpenSSL artifact is missing: %%~fF
    echo Build it first with: third_party\openssl\build.cmd !OPENSSL_CONFIG! safe
    exit /b 1
)

"!OPENSSL_STAGE!\bin\openssl.exe" version | findstr /i /c:"OpenSSL 3.5.7" >nul
if errorlevel 1 (
    echo ERROR: The !OPENSSL_CONFIG! OpenSSL stage is not OpenSSL 3.5.7.
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
echo   all       Build, CTest, stage, and verify Debug and Release.
echo   debug     Build, CTest, stage, and verify Debug only.
echo   release   Build, CTest, stage, and verify Release only.
echo.
echo Other options:
echo   clean     Remove the selected configuration work and stage first.
echo   check     Validate source, toolchain, and matching OpenSSL/Brotli stage only.
echo.
echo Build model:
echo   Makefile.msc generates the amalgamation and public sources only.
echo   CMake/MSBuild compiles and links sqlcipher.dll and sqlcipher.exe.
echo.
echo Stage directories:
echo   build\sqlcipher\x64-debug\stage
echo   build\sqlcipher\x64-release\stage
echo.
echo CTest and product smoke checks run for every build. The Tcl SQLCipher suite is not run.
exit /b 0

:show_help_error
call :show_help
exit /b 1
