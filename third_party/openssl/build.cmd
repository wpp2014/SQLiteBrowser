@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..\..") do set "PROJECT_ROOT=%%~fI"

set "OPENSSL_SRC=%SCRIPT_DIR%src"
set "OPENSSL_BUILD_ROOT=%PROJECT_ROOT%\build\openssl"
set "EXPECTED_OPENSSL_COMMIT=8cf17aaeb4599f8af87fefd810b5b5fee90fe69e"
set "EXPECTED_OPENSSL_TAG=openssl-3.5.7"
set "REQUIRED_WINDOWS_SDK=10.0.22621.0"

set "BUILD_CONFIG=all"
set "TEST_MODE=safe"
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
) else if /i "%~1"=="safe" (
    set "TEST_MODE=safe"
) else if /i "%~1"=="full" (
    set "TEST_MODE=full"
) else if /i "%~1"=="none" (
    set "TEST_MODE=none"
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
set "LC_ALL=C"
set "LANG=C"
set "LANGUAGE="
set "VSCMD_SKIP_SENDTELEMETRY=1"

echo [OpenSSL] Project root: !PROJECT_ROOT!
echo [OpenSSL] Source:       !OPENSSL_SRC!
echo [OpenSSL] Configuration: !BUILD_CONFIG!
echo [OpenSSL] Test mode:     !TEST_MODE!
if "!CLEAN_BUILD!"=="1" echo [OpenSSL] Clean rebuild: yes
if "!CHECK_ONLY!"=="1" echo [OpenSSL] Check only: yes
echo.

call :require_tool git.exe "Git is required to validate and initialise the OpenSSL submodule."
if errorlevel 1 exit /b 1

if not exist "!OPENSSL_SRC!\Configure" (
    if "!CHECK_ONLY!"=="1" (
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
call :require_tool rc.exe "Install Windows SDK 10.0.22621.0."
if errorlevel 1 exit /b 1
call :require_tool dumpbin.exe "Install the Visual Studio 2022 MSVC v143 x64/x86 build tools."
if errorlevel 1 exit /b 1
call :require_tool certutil.exe "certutil.exe is required to record staged DLL SHA-256 hashes."
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

if /i not "!TEST_MODE!"=="none" (
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

if "!CHECK_ONLY!"=="1" (
    echo [OpenSSL] Environment check completed successfully. No build was performed.
    exit /b 0
)

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
echo [OpenSSL] Requested build completed successfully.
echo [OpenSSL] Build root: !OPENSSL_BUILD_ROOT!
if /i "!TEST_MODE!"=="safe" echo [OpenSSL] WARNING: test_bio_dgram was excluded; this is not a full test pass.
if /i "!TEST_MODE!"=="none" echo [OpenSSL] WARNING: nmake test was skipped.
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

set "CURRENT_BUILD_DIR=!OPENSSL_BUILD_ROOT!\x64-!CURRENT_CONFIG!"
set "CURRENT_WORK_DIR=!CURRENT_BUILD_DIR!\work"
set "CURRENT_STAGE_DIR=!CURRENT_BUILD_DIR!\stage"

echo.
echo ================================================================================
echo [OpenSSL] Building !CURRENT_CONFIG! x64
echo [OpenSSL] Work:  !CURRENT_WORK_DIR!
echo [OpenSSL] Stage: !CURRENT_STAGE_DIR!
echo ================================================================================

if "!CLEAN_BUILD!"=="1" (
    call :remove_build_directory "!CURRENT_WORK_DIR!"
    if errorlevel 1 exit /b 1
    call :remove_build_directory "!CURRENT_STAGE_DIR!"
    if errorlevel 1 exit /b 1
)

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

echo [OpenSSL] Compiling !CURRENT_CONFIG!...
nmake
if errorlevel 1 (
    echo ERROR: nmake failed for !CURRENT_CONFIG!.
    popd
    exit /b 1
)

if /i "!TEST_MODE!"=="safe" (
    echo [OpenSSL] Running safe test suite; test_bio_dgram is excluded.
    nmake TESTS="-test_bio_dgram" VFP=1 test
    if errorlevel 1 (
        echo ERROR: The safe OpenSSL test suite failed for !CURRENT_CONFIG!.
        popd
        exit /b 1
    )
) else if /i "!TEST_MODE!"=="full" (
    call :check_ipv6_udp_loopback
    if errorlevel 1 (
        echo ERROR: Full tests were not started because IPv6 UDP loopback is unavailable.
        echo Use safe mode on this development machine, or fix the network filter conflict.
        popd
        exit /b 1
    )
    echo [OpenSSL] Running the full OpenSSL test suite.
    nmake VFP=1 test
    if errorlevel 1 (
        echo ERROR: The full OpenSSL test suite failed for !CURRENT_CONFIG!.
        popd
        exit /b 1
    )
) else (
    echo [OpenSSL] WARNING: Tests are skipped for !CURRENT_CONFIG!.
)

echo [OpenSSL] Installing software into the project stage...
nmake install_sw
if errorlevel 1 (
    echo ERROR: nmake install_sw failed for !CURRENT_CONFIG!.
    popd
    exit /b 1
)
nmake install_ssldirs
if errorlevel 1 (
    echo ERROR: nmake install_ssldirs failed for !CURRENT_CONFIG!.
    popd
    exit /b 1
)

popd

call :verify_stage "!CURRENT_CONFIG!" "!CURRENT_STAGE_DIR!"
if errorlevel 1 exit /b 1

call :write_manifest "!CURRENT_CONFIG!" "!CURRENT_STAGE_DIR!"
if errorlevel 1 exit /b 1

echo [OpenSSL] !CURRENT_CONFIG! build and stage verification completed.
exit /b 0

:verify_stage
set "VERIFY_CONFIG=%~1"
set "VERIFY_STAGE=%~2"

for %%F in (
    "!VERIFY_STAGE!\bin\openssl.exe"
    "!VERIFY_STAGE!\bin\libcrypto-3-x64.dll"
    "!VERIFY_STAGE!\bin\libssl-3-x64.dll"
    "!VERIFY_STAGE!\include\openssl\opensslv.h"
    "!VERIFY_STAGE!\lib\libcrypto.lib"
    "!VERIFY_STAGE!\lib\libssl.lib"
    "!VERIFY_STAGE!\lib\cmake\OpenSSL\OpenSSLConfig.cmake"
    "!VERIFY_STAGE!\lib\ossl-modules\legacy.dll"
) do (
    if not exist "%%~fF" (
        echo ERROR: Expected staged artifact is missing: %%~fF
        exit /b 1
    )
)

"!VERIFY_STAGE!\bin\openssl.exe" version -a
if errorlevel 1 (
    echo ERROR: Staged openssl.exe cannot report its version.
    exit /b 1
)
"!VERIFY_STAGE!\bin\openssl.exe" list -providers
if errorlevel 1 (
    echo ERROR: The OpenSSL default provider could not be loaded.
    exit /b 1
)
"!VERIFY_STAGE!\bin\openssl.exe" list -providers -provider default -provider legacy
if errorlevel 1 (
    echo ERROR: The staged OpenSSL legacy provider could not be loaded.
    exit /b 1
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

exit /b 0

:write_manifest
set "MANIFEST_CONFIG=%~1"
set "MANIFEST_STAGE=%~2"
set "MANIFEST_PATH=!MANIFEST_STAGE!\build-manifest.txt"

>"!MANIFEST_PATH!" echo OpenSSL build manifest
>>"!MANIFEST_PATH!" echo ======================
>>"!MANIFEST_PATH!" echo OpenSSL tag: !EXPECTED_OPENSSL_TAG!
>>"!MANIFEST_PATH!" echo OpenSSL commit: !OPENSSL_COMMIT!
>>"!MANIFEST_PATH!" echo Configuration: !MANIFEST_CONFIG!
>>"!MANIFEST_PATH!" echo Configure target: VC-WIN64A
>>"!MANIFEST_PATH!" echo Configure options: shared !CONFIGURE_MODE! no-demos --libdir=lib
>>"!MANIFEST_PATH!" echo Test mode: !TEST_MODE!
>>"!MANIFEST_PATH!" echo Visual Studio: !VS_EDITION! 2022
>>"!MANIFEST_PATH!" echo Visual Studio root: !VS_ROOT!
>>"!MANIFEST_PATH!" echo MSVC tools: !VCToolsVersion!
>>"!MANIFEST_PATH!" echo Windows SDK: !WindowsSDKVersion!
>>"!MANIFEST_PATH!" echo Stage: !MANIFEST_STAGE!
>>"!MANIFEST_PATH!" echo.
>>"!MANIFEST_PATH!" "!MANIFEST_STAGE!\bin\openssl.exe" version -a
>>"!MANIFEST_PATH!" echo.
>>"!MANIFEST_PATH!" perl -e "print qq(Perl: $^V\n)"
>>"!MANIFEST_PATH!" nasm -v
>>"!MANIFEST_PATH!" echo.
>>"!MANIFEST_PATH!" certutil -hashfile "!MANIFEST_STAGE!\bin\libcrypto-3-x64.dll" SHA256
>>"!MANIFEST_PATH!" certutil -hashfile "!MANIFEST_STAGE!\bin\libssl-3-x64.dll" SHA256

if errorlevel 1 (
    echo ERROR: Failed to write build manifest: !MANIFEST_PATH!
    exit /b 1
)
echo [OpenSSL] Manifest: !MANIFEST_PATH!
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
set "EXPECTED_PREFIX=!OPENSSL_BUILD_ROOT!\x64-"

echo(!REMOVE_TARGET!| findstr /b /i /l /c:"!EXPECTED_PREFIX!" >nul
if errorlevel 1 (
    echo ERROR: Refusing to remove a directory outside the OpenSSL build root.
    echo Target: !REMOVE_TARGET!
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
echo   third_party\openssl\build.cmd [all^|debug^|release] [safe^|full^|none] [clean]
echo   third_party\openssl\build.cmd check
echo   third_party\openssl\build.cmd --help
echo.
echo Defaults:
echo   all safe
echo.
echo Build selection:
echo   all       Build Debug and Release.
echo   debug     Build Debug only.
echo   release   Build Release only.
echo.
echo Test selection:
echo   safe      Run all OpenSSL tests except test_bio_dgram.
echo   full      Require IPv6 UDP loopback, then run the full suite.
echo   none      Skip nmake test; staged artifacts are still verified.
echo.
echo Other options:
echo   clean     Remove the selected OpenSSL work and stage directories first.
echo   check     Validate source revision and required tools without building.
echo.
echo Stage directories:
echo   build\openssl\x64-debug\stage
echo   build\openssl\x64-release\stage
exit /b 0

:show_help_error
call :show_help
exit /b 1
