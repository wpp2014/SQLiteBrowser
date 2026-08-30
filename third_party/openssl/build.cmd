@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "PROJECT_ROOT=%%~fI"

set "OPENSSL_SRC=%SCRIPT_DIR%src"
set "OUTPUT_ROOT=%PROJECT_ROOT%\output"
set "EXPECTED_OPENSSL_COMMIT=8cf17aaeb4599f8af87fefd810b5b5fee90fe69e"
set "EXPECTED_OPENSSL_TAG=openssl-3.5.7"
set "EXPECTED_BROTLI_COMMIT=028fb5a23661f123017c060daa546b55cf4bde29"
set "EXPECTED_BROTLI_TAG=v1.2.0"
set "REQUIRED_WINDOWS_SDK=10.0.26100.0"

set "ACTION=build"
set "ACTION_EXPLICIT=0"
set "BUILD_CONFIG=all"
set "TEST_MODE=safe"
set "TEST_MODE_EXPLICIT=0"

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
) else if /i "%~1"=="safe" (
    set "TEST_MODE=safe"
    set "TEST_MODE_EXPLICIT=1"
) else if /i "%~1"=="full" (
    set "TEST_MODE=full"
    set "TEST_MODE_EXPLICIT=1"
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
if /i not "!ACTION!"=="test" if "!TEST_MODE_EXPLICIT!"=="1" (
    echo ERROR: safe and full are valid only with the test action.
    exit /b 1
)
set "LC_ALL=C"
set "LANG=C"
set "LANGUAGE="
set "VSCMD_SKIP_SENDTELEMETRY=1"

echo [OpenSSL] Project root: !PROJECT_ROOT!
echo [OpenSSL] Source:       !OPENSSL_SRC!
echo [OpenSSL] Action:        !ACTION!
echo [OpenSSL] Configuration: !BUILD_CONFIG!
if /i "!ACTION!"=="test" echo [OpenSSL] Test mode:     !TEST_MODE!
echo.

call :require_tool git.exe "Git is required to validate and initialise the OpenSSL submodule."
if errorlevel 1 exit /b 1

if not exist "!OPENSSL_SRC!\Configure" (
    if /i "!ACTION!"=="check" (
        echo ERROR: The OpenSSL submodule is not initialised: !OPENSSL_SRC!
        echo Run: git submodule update --init --recursive
        exit /b 1
    )

    echo [OpenSSL] Initialising the OpenSSL submodule...
    git -C "!PROJECT_ROOT!" submodule update --init --recursive -- third_party/openssl/src
    if errorlevel 1 (
        echo ERROR: Failed to initialise the OpenSSL submodule.
        exit /b 1
    )
)

if not exist "!OPENSSL_SRC!\Configure" (
    echo ERROR: OpenSSL Configure was not found after submodule initialisation.
    exit /b 1
)

set "OPENSSL_COMMIT="
for /f "usebackq delims=" %%I in (`git -C "!OPENSSL_SRC!" rev-parse HEAD 2^>nul`) do set "OPENSSL_COMMIT=%%I"
if not defined OPENSSL_COMMIT (
    echo ERROR: Unable to read the OpenSSL submodule commit.
    exit /b 1
)
if /i not "!OPENSSL_COMMIT!"=="!EXPECTED_OPENSSL_COMMIT!" (
    echo ERROR: Unexpected OpenSSL submodule commit.
    echo Expected: !EXPECTED_OPENSSL_COMMIT! ^(!EXPECTED_OPENSSL_TAG!^)
    echo Actual:   !OPENSSL_COMMIT!
    echo Refusing to build an unverified OpenSSL revision.
    exit /b 1
)

set "OPENSSL_DIRTY="
for /f "usebackq delims=" %%I in (`git -C "!OPENSSL_SRC!" status --porcelain=v1 --untracked-files=all --ignore-submodules=all 2^>nul`) do set "OPENSSL_DIRTY=1"
if defined OPENSSL_DIRTY (
    echo ERROR: The OpenSSL source submodule has local changes.
    echo Commit, stash, or remove those changes before building.
    git -C "!OPENSSL_SRC!" status --short --ignore-submodules=all
    exit /b 1
)

call :find_visual_studio
if errorlevel 1 exit /b 1

echo [OpenSSL] Visual Studio: !VS_EDITION! 2022
echo [OpenSSL] Initialising MSVC x64 with Windows SDK !REQUIRED_WINDOWS_SDK!...
call "!VS_DEVCMD!" -no_logo -arch=x64 -host_arch=x64 -winsdk=!REQUIRED_WINDOWS_SDK!
if errorlevel 1 (
    echo ERROR: Visual Studio developer environment initialisation failed.
    exit /b 1
)

call :require_tool perl.exe "Install a native Windows Perl distribution, preferably Strawberry Perl, and add it to PATH."
if errorlevel 1 exit /b 1
call :require_tool nasm.exe "Install NASM and add nasm.exe to PATH."
if errorlevel 1 exit /b 1
call :require_tool cl.exe "Install the Visual Studio 2022 Desktop development with C++ workload."
if errorlevel 1 exit /b 1
call :require_tool link.exe "Install the Visual Studio 2022 MSVC v143 x64/x86 build tools."
if errorlevel 1 exit /b 1
call :require_tool lib.exe "Install the Visual Studio 2022 MSVC v143 x64/x86 build tools."
if errorlevel 1 exit /b 1
call :require_tool nmake.exe "Install the Visual Studio 2022 MSVC v143 x64/x86 build tools."
if errorlevel 1 exit /b 1
call :require_tool rc.exe "Install Windows SDK !REQUIRED_WINDOWS_SDK!."
if errorlevel 1 exit /b 1
call :require_tool dumpbin.exe "Install the Visual Studio 2022 MSVC v143 x64/x86 build tools."
if errorlevel 1 exit /b 1
call :require_tool certutil.exe "certutil.exe is required to record staged DLL SHA-256 hashes."
if errorlevel 1 exit /b 1
call :require_tool fc.exe "Windows fc.exe is required to compare staged Brotli runtime DLLs."
if errorlevel 1 exit /b 1
if /i "!TEST_MODE!"=="full" (
    call :require_tool powershell.exe "Windows PowerShell is required for the IPv6 UDP preflight used by full tests."
    if errorlevel 1 exit /b 1
)

perl -e "exit(($] >= 5.010) ? 0 : 1)"
if errorlevel 1 (
    echo ERROR: Perl 5.10.0 or newer is required.
    perl -v
    exit /b 1
)

perl -I"!OPENSSL_SRC!\external\perl\Text-Template-1.56\lib" -MText::Template=1.46 -e "exit 0"
if errorlevel 1 (
    echo ERROR: Perl module Text::Template is unavailable.
    echo Use a complete native Windows Perl installation such as Strawberry Perl.
    exit /b 1
)

if /i "!ACTION!"=="test" (
    perl -e "use Test::More 0.96; exit 0"
    if errorlevel 1 (
        echo ERROR: Perl module Test::More 0.96 or newer is required for OpenSSL tests.
        exit /b 1
    )
)

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

echo [OpenSSL] Toolchain checks passed.
echo [OpenSSL] OpenSSL revision: !EXPECTED_OPENSSL_TAG! / !OPENSSL_COMMIT!
echo [OpenSSL] MSVC tools: !VCToolsVersion!
echo [OpenSSL] Windows SDK: !WindowsSDKVersion!
perl -e "print qq([OpenSSL] Perl: $^V\n)"
nasm -v
echo.

set "TOOLCHAIN_PATH=!PATH!"

if /i "!ACTION!"=="check" (
    if /i "!BUILD_CONFIG!"=="all" (
        call :validate_brotli_stage debug
        if errorlevel 1 exit /b 1
        call :validate_brotli_stage release
        if errorlevel 1 exit /b 1
    ) else (
        call :validate_brotli_stage !BUILD_CONFIG!
        if errorlevel 1 exit /b 1
    )
    echo [OpenSSL] Environment check completed successfully. No build was performed.
    exit /b 0
)

if /i "!ACTION!"=="clean" goto dispatch_clean
if /i "!ACTION!"=="test" goto dispatch_test

if /i "!BUILD_CONFIG!"=="all" (
    call :build_one debug
    if errorlevel 1 exit /b 1
    call :build_one release
    if errorlevel 1 exit /b 1
) else (
    call :build_one !BUILD_CONFIG!
    if errorlevel 1 exit /b 1
)

echo.
echo [OpenSSL] Requested minimal product build completed successfully.
echo [OpenSSL] Output root: !OUTPUT_ROOT!
exit /b 0

:dispatch_test
if /i "!BUILD_CONFIG!"=="all" (
    call :test_one debug
    if errorlevel 1 exit /b 1
    call :test_one release
    if errorlevel 1 exit /b 1
) else (
    call :test_one !BUILD_CONFIG!
    if errorlevel 1 exit /b 1
)
echo.
echo [OpenSSL] Requested tests completed successfully.
if /i "!TEST_MODE!"=="safe" echo [OpenSSL] WARNING: test_bio_dgram was excluded; this is not a full test pass.
exit /b 0

:dispatch_clean
if /i "!BUILD_CONFIG!"=="all" (
    call :clean_one debug
    if errorlevel 1 exit /b 1
    call :clean_one release
    if errorlevel 1 exit /b 1
) else (
    call :clean_one !BUILD_CONFIG!
    if errorlevel 1 exit /b 1
)
echo [OpenSSL] Requested clean completed successfully.
exit /b 0

:set_action
if "!ACTION_EXPLICIT!"=="1" if /i not "!ACTION!"=="%~1" (
    echo ERROR: Multiple actions were specified: !ACTION! and %~1.
    exit /b 1
)
set "ACTION=%~1"
set "ACTION_EXPLICIT=1"
exit /b 0

:build_one
set "CURRENT_CONFIG=%~1"
if /i "!CURRENT_CONFIG!"=="debug" (
    set "CONFIGURE_MODE=--debug"
) else if /i "!CURRENT_CONFIG!"=="release" (
    set "CONFIGURE_MODE=--release"
) else (
    echo ERROR: Internal error: unsupported configuration !CURRENT_CONFIG!.
    exit /b 1
)

set "CURRENT_COMPONENT_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG!\build\openssl"
set "CURRENT_WORK_DIR=!CURRENT_COMPONENT_ROOT!\work"
set "CURRENT_STAGE_DIR=!CURRENT_COMPONENT_ROOT!\stage"

call :validate_brotli_stage !CURRENT_CONFIG!
if errorlevel 1 exit /b 1
set "PATH=!CURRENT_BROTLI_STAGE!\bin;!TOOLCHAIN_PATH!"
set "BROTLI_INCLUDE_DIR=!CURRENT_BROTLI_STAGE!\include"

echo.
echo ================================================================================
echo [OpenSSL] Building !CURRENT_CONFIG! x64
echo [OpenSSL] Work:  !CURRENT_WORK_DIR!
echo [OpenSSL] Stage: !CURRENT_STAGE_DIR!
echo ================================================================================

if not exist "!CURRENT_WORK_DIR!" (
    mkdir "!CURRENT_WORK_DIR!"
    if errorlevel 1 (
        echo ERROR: Unable to create work directory: !CURRENT_WORK_DIR!
        exit /b 1
    )
)

pushd "!CURRENT_WORK_DIR!"
if errorlevel 1 (
    echo ERROR: Unable to enter work directory: !CURRENT_WORK_DIR!
    exit /b 1
)

set "NEEDS_CONFIGURE=1"
if exist "makefile" if exist "configdata.pm" set "NEEDS_CONFIGURE=0"

if "!NEEDS_CONFIGURE!"=="1" (
    echo [OpenSSL] Configuring !CURRENT_CONFIG!...
    perl "!OPENSSL_SRC!\Configure" VC-WIN64A ^
        shared ^
        !CONFIGURE_MODE! ^
        enable-brotli-dynamic ^
        --with-brotli-include="!BROTLI_INCLUDE_DIR!" ^
        --prefix="!CURRENT_STAGE_DIR!" ^
        --openssldir="!CURRENT_STAGE_DIR!\ssl" ^
        --libdir=lib ^
        no-demos
    if errorlevel 1 (
        echo ERROR: OpenSSL Configure failed for !CURRENT_CONFIG!.
        popd
        exit /b 1
    )
) else (
    echo [OpenSSL] Reusing the existing !CURRENT_CONFIG! configuration.
    echo [OpenSSL] Add clean to regenerate it with the script's pinned options.
)

call :verify_brotli_configuration
if errorlevel 1 (
    popd
    exit /b 1
)

echo [OpenSSL] Compiling !CURRENT_CONFIG! Crypto and SSL library targets...
nmake build_libs
if errorlevel 1 (
    echo ERROR: nmake build_libs failed for !CURRENT_CONFIG!.
    popd
    exit /b 1
)

popd

call :remove_build_directory "!CURRENT_STAGE_DIR!" "!CURRENT_COMPONENT_ROOT!"
if errorlevel 1 exit /b 1

pushd "!CURRENT_WORK_DIR!"
if errorlevel 1 exit /b 1
echo [OpenSSL] Installing minimal development artifacts into the project stage...
nmake install_dev
if errorlevel 1 (
    echo ERROR: nmake install_dev failed for !CURRENT_CONFIG!.
    popd
    exit /b 1
)

echo [OpenSSL] Deploying the matching Brotli runtime DLLs into the OpenSSL stage...
for %%L in (brotlicommon brotlidec brotlienc) do (
    copy /y "!CURRENT_BROTLI_STAGE!\bin\%%L.dll" "!CURRENT_STAGE_DIR!\bin\%%L.dll" >nul
    if errorlevel 1 (
        echo ERROR: Failed to stage %%L.dll from !CURRENT_BROTLI_STAGE!.
        popd
        exit /b 1
    )
)

popd

call :write_manifest "!CURRENT_CONFIG!" "!CURRENT_STAGE_DIR!"
if errorlevel 1 exit /b 1

call :verify_stage "!CURRENT_CONFIG!" "!CURRENT_STAGE_DIR!"
if errorlevel 1 exit /b 1

echo [OpenSSL] !CURRENT_CONFIG! minimal build and stage verification completed.
exit /b 0

:test_one
set "CURRENT_CONFIG=%~1"
if /i not "!CURRENT_CONFIG!"=="debug" if /i not "!CURRENT_CONFIG!"=="release" exit /b 1
set "CURRENT_COMPONENT_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG!\build\openssl"
set "CURRENT_WORK_DIR=!CURRENT_COMPONENT_ROOT!\work"
set "CURRENT_STAGE_DIR=!CURRENT_COMPONENT_ROOT!\stage"

call :validate_brotli_stage !CURRENT_CONFIG!
if errorlevel 1 exit /b 1
set "PATH=!CURRENT_BROTLI_STAGE!\bin;!TOOLCHAIN_PATH!"
set "BROTLI_INCLUDE_DIR=!CURRENT_BROTLI_STAGE!\include"

if not exist "!CURRENT_WORK_DIR!\makefile" if not exist "!CURRENT_WORK_DIR!\Makefile" (
    echo ERROR: OpenSSL !CURRENT_CONFIG! has not been configured.
    echo Run: third_party\openssl\build.cmd build !CURRENT_CONFIG!
    exit /b 1
)
call :verify_stage "!CURRENT_CONFIG!" "!CURRENT_STAGE_DIR!"
if errorlevel 1 (
    echo ERROR: OpenSSL !CURRENT_CONFIG! staged product is missing or invalid.
    echo Run: third_party\openssl\build.cmd build !CURRENT_CONFIG!
    exit /b 1
)

pushd "!CURRENT_WORK_DIR!"
if errorlevel 1 exit /b 1
call :verify_brotli_configuration
if errorlevel 1 (
    popd
    exit /b 1
)

if /i "!TEST_MODE!"=="full" (
    call :check_ipv6_udp_loopback
    if errorlevel 1 (
        echo ERROR: Full tests were not started because IPv6 UDP loopback is unavailable.
        echo Use safe mode on this development machine, or fix the network filter conflict.
        popd
        exit /b 1
    )
    echo [OpenSSL] Running the full OpenSSL test suite for !CURRENT_CONFIG!.
    nmake VFP=1 test
) else (
    echo [OpenSSL] Running the safe OpenSSL test suite for !CURRENT_CONFIG!; test_bio_dgram is excluded.
    nmake TESTS="-test_bio_dgram" VFP=1 test
)
if errorlevel 1 (
    echo ERROR: The !TEST_MODE! OpenSSL test suite failed for !CURRENT_CONFIG!.
    popd
    exit /b 1
)

echo [OpenSSL] Running focused Brotli BIO and certificate-compression tests...
nmake TESTS="test_bio_comp test_cert_comp test_tls13certcomp" VFP=1 test
if errorlevel 1 (
    echo ERROR: Focused OpenSSL Brotli integration tests failed for !CURRENT_CONFIG!.
    popd
    exit /b 1
)
popd

call :write_test_manifest "!CURRENT_CONFIG!" "!CURRENT_STAGE_DIR!"
if errorlevel 1 exit /b 1
echo [OpenSSL] !CURRENT_CONFIG! !TEST_MODE! tests completed; product artifacts were not reinstalled.
exit /b 0

:clean_one
set "CURRENT_CONFIG=%~1"
set "CURRENT_COMPONENT_ROOT=!OUTPUT_ROOT!\x64-shared-!CURRENT_CONFIG!\build\openssl"
call :remove_build_directory "!CURRENT_COMPONENT_ROOT!" "!CURRENT_COMPONENT_ROOT!"
exit /b !ERRORLEVEL!

:validate_brotli_stage
set "BROTLI_CONFIG=%~1"
set "BROTLI_CONFIG_TITLE=Release"
set "BROTLI_EXPECTED_CRT=/MD"
if /i "!BROTLI_CONFIG!"=="debug" (
    set "BROTLI_CONFIG_TITLE=Debug"
    set "BROTLI_EXPECTED_CRT=/MDd"
) else if /i not "!BROTLI_CONFIG!"=="release" (
    echo ERROR: Internal error: unsupported Brotli configuration !BROTLI_CONFIG!.
    exit /b 1
)

set "CURRENT_BROTLI_STAGE=!OUTPUT_ROOT!\x64-shared-!BROTLI_CONFIG!\build\brotli\stage"
set "BROTLI_MANIFEST=!CURRENT_BROTLI_STAGE!\build-manifest.txt"

for %%F in (
    "!CURRENT_BROTLI_STAGE!\bin\brotlicommon.dll"
    "!CURRENT_BROTLI_STAGE!\bin\brotlidec.dll"
    "!CURRENT_BROTLI_STAGE!\bin\brotlienc.dll"
    "!CURRENT_BROTLI_STAGE!\include\brotli\decode.h"
    "!CURRENT_BROTLI_STAGE!\include\brotli\encode.h"
    "!BROTLI_MANIFEST!"
) do (
    if not exist "%%~fF" (
        echo ERROR: Matching !BROTLI_CONFIG_TITLE! Brotli stage is incomplete: %%~fF
        echo Run: third_party\brotli\build.cmd build !BROTLI_CONFIG!
        exit /b 1
    )
)

for %%L in (brotlicommon brotlidec brotlienc) do (
    dumpbin /headers "!CURRENT_BROTLI_STAGE!\bin\%%L.dll" | findstr /i /c:"8664 machine (x64)" >nul
    if errorlevel 1 (
        echo ERROR: Brotli !BROTLI_CONFIG_TITLE! %%L.dll is not x64.
        exit /b 1
    )
)

for %%M in (
    "Brotli tag: !EXPECTED_BROTLI_TAG!"
    "Brotli commit: !EXPECTED_BROTLI_COMMIT!"
    "Configuration: !BROTLI_CONFIG_TITLE!"
    "Architecture: x64"
    "Visual Studio: !VS_EDITION! 2022"
    "MSVC tools: !VCToolsVersion!"
    "Windows SDK: !REQUIRED_WINDOWS_SDK!"
    "CRT: !BROTLI_EXPECTED_CRT!"
    "Library type: shared"
    "Project shared smoke test: not run"
    "Runtime version verification: not run"
) do (
    findstr /x /l /c:"%%~M" "!BROTLI_MANIFEST!" >nul
    if errorlevel 1 (
        echo ERROR: Brotli manifest is missing the required value: %%~M
        echo Rebuild the matching Brotli stage with: third_party\brotli\build.cmd build !BROTLI_CONFIG!
        exit /b 1
    )
)

echo [OpenSSL] Matching Brotli stage validated: !CURRENT_BROTLI_STAGE!
exit /b 0

:verify_brotli_configuration
if not exist "configdata.pm" (
    echo ERROR: OpenSSL configdata.pm is missing after configuration.
    exit /b 1
)

perl configdata.pm --options | findstr /x /c:"    brotli" >nul
if errorlevel 1 (
    echo ERROR: The existing OpenSSL configuration does not enable Brotli.
    echo Rerun this configuration with clean to regenerate the pinned Configure options.
    exit /b 1
)

perl configdata.pm --options | findstr /x /c:"    brotli-dynamic" >nul
if errorlevel 1 (
    echo ERROR: The existing OpenSSL configuration does not enable dynamic Brotli loading.
    echo Rerun this configuration with clean to regenerate the pinned Configure options.
    exit /b 1
)

perl configdata.pm --command-line | findstr /i /l /c:"--with-brotli-include=!BROTLI_INCLUDE_DIR!" >nul
if errorlevel 1 (
    echo ERROR: The existing OpenSSL configuration does not use the matching Brotli include stage.
    echo Expected: --with-brotli-include=!BROTLI_INCLUDE_DIR!
    echo Rerun this configuration with clean to regenerate the pinned Configure options.
    exit /b 1
)

echo [OpenSSL] Dynamic Brotli configuration is enabled.
exit /b 0

:verify_stage
set "VERIFY_CONFIG=%~1"
set "VERIFY_STAGE=%~2"

for %%F in (
    "!VERIFY_STAGE!\bin\libcrypto-3-x64.dll"
    "!VERIFY_STAGE!\bin\libcrypto-3-x64.pdb"
    "!VERIFY_STAGE!\bin\libssl-3-x64.dll"
    "!VERIFY_STAGE!\bin\libssl-3-x64.pdb"
    "!VERIFY_STAGE!\include\openssl\opensslv.h"
    "!VERIFY_STAGE!\lib\libcrypto.lib"
    "!VERIFY_STAGE!\lib\libssl.lib"
    "!VERIFY_STAGE!\lib\cmake\OpenSSL\OpenSSLConfig.cmake"
    "!VERIFY_STAGE!\bin\brotlicommon.dll"
    "!VERIFY_STAGE!\bin\brotlidec.dll"
    "!VERIFY_STAGE!\bin\brotlienc.dll"
    "!VERIFY_STAGE!\build-manifest.txt"
) do (
    if not exist "%%~fF" (
        echo ERROR: Expected staged artifact is missing: %%~fF
        exit /b 1
    )
)

for %%L in (libcrypto-3-x64 libssl-3-x64) do (
    dumpbin /headers "!VERIFY_STAGE!\bin\%%L.dll" | findstr /i /c:"8664 machine (x64)" >nul
    if errorlevel 1 (
        echo ERROR: Staged %%L.dll is not x64.
        exit /b 1
    )
)

findstr /x /c:"Tests: not run" "!VERIFY_STAGE!\build-manifest.txt" >nul
if errorlevel 1 (
    echo ERROR: OpenSSL build manifest has an unexpected test status.
    exit /b 1
)

for %%L in (brotlicommon brotlidec brotlienc) do (
    fc.exe /b "!CURRENT_BROTLI_STAGE!\bin\%%L.dll" "!VERIFY_STAGE!\bin\%%L.dll" >nul
    if errorlevel 1 (
        echo ERROR: Staged %%L.dll does not match the validated !VERIFY_CONFIG! Brotli stage.
        exit /b 1
    )
)

dumpbin /dependents "!VERIFY_STAGE!\bin\libssl-3-x64.dll" | findstr /i /c:"libcrypto-3-x64.dll" >nul
if errorlevel 1 (
    echo ERROR: Staged libssl does not depend on the matching libcrypto DLL.
    exit /b 1
)

dumpbin /dependents "!VERIFY_STAGE!\bin\libcrypto-3-x64.dll" | findstr /i /c:"brotli" >nul
if not errorlevel 1 (
    echo ERROR: Dynamic Brotli mode is expected, but libcrypto has a direct Brotli DLL dependency.
    exit /b 1
)

for %%E in (COMP_brotli COMP_brotli_oneshot BIO_f_brotli) do (
    dumpbin /exports "!VERIFY_STAGE!\bin\libcrypto-3-x64.dll" | findstr /c:" %%E" >nul
    if errorlevel 1 (
        echo ERROR: Staged libcrypto does not export %%E.
        exit /b 1
    )
)

for %%L in (brotlicommon brotlidec brotlienc) do (
    dumpbin /headers "!VERIFY_STAGE!\bin\%%L.dll" | findstr /i /c:"8664 machine (x64)" >nul
    if errorlevel 1 (
        echo ERROR: Staged %%L.dll is not x64.
        exit /b 1
    )
)

if /i "!VERIFY_CONFIG!"=="release" (
    dumpbin /dependents "!VERIFY_STAGE!\bin\libcrypto-3-x64.dll" | findstr /i /c:"VCRUNTIME140D.dll" /c:"ucrtbased.dll" >nul
    if not errorlevel 1 (
        echo ERROR: Release libcrypto unexpectedly depends on the Debug CRT.
        exit /b 1
    )
    dumpbin /dependents "!VERIFY_STAGE!\bin\libssl-3-x64.dll" | findstr /i /c:"VCRUNTIME140D.dll" /c:"ucrtbased.dll" >nul
    if not errorlevel 1 (
        echo ERROR: Release libssl unexpectedly depends on the Debug CRT.
        exit /b 1
    )
) else (
    dumpbin /dependents "!VERIFY_STAGE!\bin\libcrypto-3-x64.dll" | findstr /i /c:"VCRUNTIME140D.dll" >nul
    if errorlevel 1 (
        echo ERROR: Debug libcrypto does not depend on the expected Debug CRT.
        exit /b 1
    )
    dumpbin /dependents "!VERIFY_STAGE!\bin\libssl-3-x64.dll" | findstr /i /c:"VCRUNTIME140D.dll" >nul
    if errorlevel 1 (
        echo ERROR: Debug libssl does not depend on the expected Debug CRT.
        exit /b 1
    )
)

for %%F in (
    "!VERIFY_STAGE!\bin\openssl.exe"
    "!VERIFY_STAGE!\lib\ossl-modules\legacy.dll"
    "!VERIFY_STAGE!\lib\engines-3\*.dll"
) do if exist "%%~fF" (
    echo ERROR: Non-minimal OpenSSL artifact leaked into stage: %%~fF
    exit /b 1
)

set "VERIFY_COMPILER_PDB="
for /r "!VERIFY_STAGE!" %%F in (vc143.pdb) do if exist "%%~fF" set "VERIFY_COMPILER_PDB=%%~fF"
if defined VERIFY_COMPILER_PDB (
    echo ERROR: Compiler PDB vc143.pdb must not be deployed to the OpenSSL stage.
    exit /b 1
)

exit /b 0

:write_manifest
set "MANIFEST_CONFIG=%~1"
set "MANIFEST_STAGE=%~2"
set "MANIFEST_PATH=!MANIFEST_STAGE!\build-manifest.txt"

call :calculate_sha256 "!MANIFEST_STAGE!\bin\libcrypto-3-x64.dll" CRYPTO_DLL_SHA256
if errorlevel 1 exit /b 1
call :calculate_sha256 "!MANIFEST_STAGE!\bin\libcrypto-3-x64.pdb" CRYPTO_PDB_SHA256
if errorlevel 1 exit /b 1
call :calculate_sha256 "!MANIFEST_STAGE!\bin\libssl-3-x64.dll" SSL_DLL_SHA256
if errorlevel 1 exit /b 1
call :calculate_sha256 "!MANIFEST_STAGE!\bin\libssl-3-x64.pdb" SSL_PDB_SHA256
if errorlevel 1 exit /b 1
for %%F in (brotlicommon brotlidec brotlienc) do (
    call :calculate_sha256 "!MANIFEST_STAGE!\bin\%%F.dll" %%F_DLL_SHA256
    if errorlevel 1 exit /b 1
)
call :calculate_sha256 "!MANIFEST_STAGE!\lib\libcrypto.lib" HASH_libcrypto_lib
if errorlevel 1 exit /b 1
call :calculate_sha256 "!MANIFEST_STAGE!\lib\libssl.lib" HASH_libssl_lib
if errorlevel 1 exit /b 1

>"!MANIFEST_PATH!" echo OpenSSL build manifest
>>"!MANIFEST_PATH!" echo ======================
>>"!MANIFEST_PATH!" echo OpenSSL tag: !EXPECTED_OPENSSL_TAG!
>>"!MANIFEST_PATH!" echo OpenSSL commit: !OPENSSL_COMMIT!
>>"!MANIFEST_PATH!" echo Configuration: !MANIFEST_CONFIG!
>>"!MANIFEST_PATH!" echo Configure target: VC-WIN64A
>>"!MANIFEST_PATH!" echo Configure options: shared !CONFIGURE_MODE! enable-brotli-dynamic no-demos --libdir=lib
>>"!MANIFEST_PATH!" echo Brotli tag: !EXPECTED_BROTLI_TAG!
>>"!MANIFEST_PATH!" echo Brotli commit: !EXPECTED_BROTLI_COMMIT!
>>"!MANIFEST_PATH!" echo Brotli stage: !CURRENT_BROTLI_STAGE!
>>"!MANIFEST_PATH!" echo Brotli linkage: dynamic runtime loading
>>"!MANIFEST_PATH!" echo Build target: build_libs
>>"!MANIFEST_PATH!" echo Install target: install_dev
>>"!MANIFEST_PATH!" echo Tests: not run
>>"!MANIFEST_PATH!" echo Brotli integration tests: not run
>>"!MANIFEST_PATH!" echo OpenSSL CLI staged: no
>>"!MANIFEST_PATH!" echo Providers staged: no
>>"!MANIFEST_PATH!" echo Engines staged: no
>>"!MANIFEST_PATH!" echo PDB policy: linker PDBs staged; compiler PDBs excluded
>>"!MANIFEST_PATH!" echo Visual Studio: !VS_EDITION! 2022
>>"!MANIFEST_PATH!" echo Visual Studio root: !VS_ROOT!
>>"!MANIFEST_PATH!" echo MSVC tools: !VCToolsVersion!
>>"!MANIFEST_PATH!" echo Windows SDK: !WindowsSDKVersion!
>>"!MANIFEST_PATH!" echo Stage: !MANIFEST_STAGE!
>>"!MANIFEST_PATH!" perl -e "print qq(Perl: $^V\n)"
>>"!MANIFEST_PATH!" nasm -v
>>"!MANIFEST_PATH!" echo libcrypto-3-x64.dll SHA-256: !CRYPTO_DLL_SHA256!
>>"!MANIFEST_PATH!" echo libcrypto-3-x64.pdb SHA-256: !CRYPTO_PDB_SHA256!
>>"!MANIFEST_PATH!" echo libssl-3-x64.dll SHA-256: !SSL_DLL_SHA256!
>>"!MANIFEST_PATH!" echo libssl-3-x64.pdb SHA-256: !SSL_PDB_SHA256!
>>"!MANIFEST_PATH!" echo libcrypto.lib SHA-256: !HASH_libcrypto_lib!
>>"!MANIFEST_PATH!" echo libssl.lib SHA-256: !HASH_libssl_lib!
>>"!MANIFEST_PATH!" echo brotlicommon.dll SHA-256: !brotlicommon_DLL_SHA256!
>>"!MANIFEST_PATH!" echo brotlidec.dll SHA-256: !brotlidec_DLL_SHA256!
>>"!MANIFEST_PATH!" echo brotlienc.dll SHA-256: !brotlienc_DLL_SHA256!

if errorlevel 1 (
    echo ERROR: Failed to write build manifest: !MANIFEST_PATH!
    exit /b 1
)
echo [OpenSSL] Manifest: !MANIFEST_PATH!
exit /b 0

:write_test_manifest
set "TEST_CONFIG=%~1"
set "TEST_STAGE=%~2"
call :calculate_sha256 "!TEST_STAGE!\build-manifest.txt" BUILD_MANIFEST_SHA256
if errorlevel 1 exit /b 1
set "TEST_GENERAL=passed; test_bio_dgram excluded"
if /i "!TEST_MODE!"=="full" set "TEST_GENERAL=passed; IPv6 UDP preflight passed"
>"!TEST_STAGE!\test-manifest.txt" echo OpenSSL test manifest
>>"!TEST_STAGE!\test-manifest.txt" echo OpenSSL tag: !EXPECTED_OPENSSL_TAG!
>>"!TEST_STAGE!\test-manifest.txt" echo OpenSSL commit: !OPENSSL_COMMIT!
>>"!TEST_STAGE!\test-manifest.txt" echo Configuration: !TEST_CONFIG!
>>"!TEST_STAGE!\test-manifest.txt" echo Test mode: !TEST_MODE!
>>"!TEST_STAGE!\test-manifest.txt" echo Build manifest SHA-256: !BUILD_MANIFEST_SHA256!
>>"!TEST_STAGE!\test-manifest.txt" echo General test suite: !TEST_GENERAL!
>>"!TEST_STAGE!\test-manifest.txt" echo Brotli integration tests: passed
>>"!TEST_STAGE!\test-manifest.txt" echo Focused tests: test_bio_comp; test_cert_comp; test_tls13certcomp
if errorlevel 1 (
    echo ERROR: Failed to write OpenSSL test manifest.
    exit /b 1
)
exit /b 0

:calculate_sha256
set "HASH_FILE=%~1"
set "HASH_RESULT_VARIABLE=%~2"
set "HASH_OUTPUT=%TEMP%\sqlitebrowser-openssl-hash-!RANDOM!-!RANDOM!.tmp"
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
if "!HASH_VALUE:~63,1!"=="" exit /b 1
if not "!HASH_VALUE:~64,1!"=="" exit /b 1
set "!HASH_RESULT_VARIABLE!=!HASH_VALUE!"
exit /b 0

:check_ipv6_udp_loopback
echo [OpenSSL] Checking IPv6 UDP loopback before full tests...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop'; $receiver=$null; $sender=$null; try { $receiver=[Net.Sockets.UdpClient]::new([Net.Sockets.AddressFamily]::InterNetworkV6); $receiver.Client.ReceiveTimeout=2000; $receiver.Client.Bind([Net.IPEndPoint]::new([Net.IPAddress]::IPv6Loopback,0)); $endpoint=$receiver.Client.LocalEndPoint; $sender=[Net.Sockets.UdpClient]::new([Net.Sockets.AddressFamily]::InterNetworkV6); $payload=[Text.Encoding]::ASCII.GetBytes('sqlitebrowser-openssl-probe'); [void]$sender.Send($payload,$payload.Length,$endpoint); $remote=[Net.IPEndPoint]::new([Net.IPAddress]::IPv6Any,0); $received=$receiver.Receive([ref]$remote); if($received.Length -ne $payload.Length){exit 1}; exit 0 } catch { Write-Error $_; exit 1 } finally { if($sender){$sender.Dispose()}; if($receiver){$receiver.Dispose()} }"
if errorlevel 1 exit /b 1
echo [OpenSSL] IPv6 UDP loopback check passed.
exit /b 0

:remove_build_directory
set "REMOVE_TARGET=%~f1"
set "REMOVE_ALLOWED_ROOT=%~f2"
set "REMOVE_ALLOWED_STAGE=!REMOVE_ALLOWED_ROOT!\stage"

if /i not "!REMOVE_TARGET!"=="!REMOVE_ALLOWED_ROOT!" if /i not "!REMOVE_TARGET!"=="!REMOVE_ALLOWED_STAGE!" (
    echo ERROR: Refusing to remove a directory outside the selected OpenSSL component root.
    echo Target:        !REMOVE_TARGET!
    echo Allowed root:  !REMOVE_ALLOWED_ROOT!
    echo Allowed stage: !REMOVE_ALLOWED_STAGE!
    exit /b 1
)
if exist "!REMOVE_TARGET!" (
    echo [OpenSSL] Removing: !REMOVE_TARGET!
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
echo SQLiteBrowser OpenSSL 3.5.7 Windows x64 build script
echo.
echo Usage:
echo   third_party\openssl\build.cmd check [all^|debug^|release]
echo   third_party\openssl\build.cmd build [all^|debug^|release]
echo   third_party\openssl\build.cmd test [all^|debug^|release] [safe^|full]
echo   third_party\openssl\build.cmd clean [all^|debug^|release]
echo   third_party\openssl\build.cmd [all^|debug^|release]
echo   third_party\openssl\build.cmd --help
echo.
echo Defaults:
echo   build all; test defaults to safe
echo.
echo Actions:
echo   build     Build only Crypto/SSL libraries and install the minimal development stage.
echo   test      Build test-only programs/modules in work, run tests, and write test-manifest.txt.
echo   clean     Remove only the selected OpenSSL private component directory.
echo   check     Validate source, tools, and matching Brotli stages without generating output.
echo.
echo Test modes:
echo   safe      Run all OpenSSL tests except test_bio_dgram.
echo   full      Require IPv6 UDP loopback, then run the full suite.
echo.
echo Stage directories:
echo   output\x64-shared-debug\build\openssl\stage
echo   output\x64-shared-release\build\openssl\stage
echo.
echo A verified configuration-matching Brotli stage is required. Dynamic Brotli support
echo is built into OpenSSL, and all three Brotli runtime DLLs are copied into its stage.
echo The build action does not compile tests, openssl.exe, standalone provider modules, or engines.
exit /b 0

:show_help_error
call :show_help
exit /b 1
