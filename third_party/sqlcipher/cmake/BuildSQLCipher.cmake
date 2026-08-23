cmake_minimum_required(VERSION 3.21)

set(_required_variables
    SQLCIPHER_CONFIGURATION
    SQLCIPHER_SOURCE_DIR
    SQLCIPHER_STAGE_ROOT
    SQLCIPHER_OPENSSL_ROOT_DEBUG
    SQLCIPHER_OPENSSL_ROOT_RELEASE
    SQLCIPHER_VS_DEVCMD
    SQLCIPHER_VS_EDITION
    SQLCIPHER_WINDOWS_SDK_VERSION
    SQLCIPHER_EXPECTED_TAG
    SQLCIPHER_EXPECTED_COMMIT
    SQLCIPHER_DEFINITIONS
    SQLCIPHER_BUILD_CLI
)
foreach(_variable IN LISTS _required_variables)
    if(NOT DEFINED ${_variable})
        message(FATAL_ERROR "Missing required variable: ${_variable}")
    endif()
endforeach()

if(SQLCIPHER_CONFIGURATION STREQUAL "Debug")
    set(_configuration_lower "debug")
    set(_debug_level 3)
    set(_crt "/MDd")
    set(_nmake_ldflags "/DEBUG")
    set(_openssl_root "${SQLCIPHER_OPENSSL_ROOT_DEBUG}")
elseif(SQLCIPHER_CONFIGURATION STREQUAL "Release")
    set(_configuration_lower "release")
    set(_debug_level 0)
    set(_crt "/MD")
    set(_nmake_ldflags "")
    set(_openssl_root "${SQLCIPHER_OPENSSL_ROOT_RELEASE}")
else()
    message(FATAL_ERROR
        "Unsupported SQLCipher configuration: ${SQLCIPHER_CONFIGURATION}. "
        "Use Debug or Release."
    )
endif()

foreach(_path IN ITEMS
    "${SQLCIPHER_SOURCE_DIR}"
    "${SQLCIPHER_STAGE_ROOT}"
    "${_openssl_root}"
)
    if(_path MATCHES "[ \t]")
        message(FATAL_ERROR
            "The first SQLCipher NMake wrapper does not support paths containing spaces: ${_path}"
        )
    endif()
endforeach()

if(SQLCIPHER_DEFINITIONS MATCHES "[&|<>^]")
    message(FATAL_ERROR "SQLCIPHER_DEFINITIONS contains unsupported cmd.exe metacharacters.")
endif()

if(NOT EXISTS "${SQLCIPHER_SOURCE_DIR}/Makefile.msc"
   OR NOT EXISTS "${SQLCIPHER_SOURCE_DIR}/src/sqlcipher.c")
    message(FATAL_ERROR "SQLCipher source is incomplete: ${SQLCIPHER_SOURCE_DIR}")
endif()

if(NOT EXISTS "${SQLCIPHER_VS_DEVCMD}")
    message(FATAL_ERROR "VsDevCmd.bat was not found: ${SQLCIPHER_VS_DEVCMD}")
endif()

set(_openssl_required_files
    "${_openssl_root}/include/openssl/opensslv.h"
    "${_openssl_root}/lib/libcrypto.lib"
    "${_openssl_root}/bin/libcrypto-3-x64.dll"
)
foreach(_file IN LISTS _openssl_required_files)
    if(NOT EXISTS "${_file}")
        message(FATAL_ERROR
            "Required ${SQLCIPHER_CONFIGURATION} OpenSSL artifact is missing: ${_file}. "
            "Complete the matching OpenSSL build first."
        )
    endif()
endforeach()

find_program(_git_executable NAMES git REQUIRED)
execute_process(
    COMMAND "${_git_executable}" -C "${SQLCIPHER_SOURCE_DIR}" rev-parse HEAD
    RESULT_VARIABLE _git_revision_result
    OUTPUT_VARIABLE _actual_commit
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_VARIABLE _git_revision_error
)
if(NOT _git_revision_result EQUAL 0)
    message(FATAL_ERROR "Unable to read SQLCipher commit: ${_git_revision_error}")
endif()
if(NOT _actual_commit STREQUAL SQLCIPHER_EXPECTED_COMMIT)
    message(FATAL_ERROR
        "Unexpected SQLCipher commit. Expected ${SQLCIPHER_EXPECTED_COMMIT} "
        "(${SQLCIPHER_EXPECTED_TAG}), got ${_actual_commit}."
    )
endif()

execute_process(
    COMMAND "${_git_executable}" -C "${SQLCIPHER_SOURCE_DIR}"
        status --porcelain=v1 --untracked-files=all --ignore-submodules=all
    RESULT_VARIABLE _git_status_result
    OUTPUT_VARIABLE _git_status
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_VARIABLE _git_status_error
)
if(NOT _git_status_result EQUAL 0)
    message(FATAL_ERROR "Unable to inspect SQLCipher source status: ${_git_status_error}")
endif()
if(_git_status)
    message(FATAL_ERROR
        "The SQLCipher source submodule has local changes. Refusing to build:\n${_git_status}"
    )
endif()

set(_configuration_root "${SQLCIPHER_STAGE_ROOT}/x64-${_configuration_lower}")
set(_work_dir "${_configuration_root}/work")
set(_stage_dir "${_configuration_root}/stage")
set(_stage_bin "${_stage_dir}/bin")
set(_stage_include "${_stage_dir}/include/sqlcipher")
set(_stage_lib "${_stage_dir}/lib")
set(_stage_pdb "${_stage_dir}/pdb")

file(MAKE_DIRECTORY
    "${_work_dir}"
    "${_stage_bin}"
    "${_stage_include}"
    "${_stage_lib}"
    "${_stage_pdb}"
)

file(TO_NATIVE_PATH "${SQLCIPHER_SOURCE_DIR}" _source_native)
file(TO_NATIVE_PATH "${_work_dir}" _work_native)
file(TO_NATIVE_PATH "${_openssl_root}" _openssl_native)
file(TO_NATIVE_PATH "${SQLCIPHER_VS_DEVCMD}" _vs_devcmd_native)

set(_targets "sqlcipher.dll sqlite3.h sqlite3ext.h sqlite3session.h")
if(SQLCIPHER_BUILD_CLI)
    string(APPEND _targets " sqlcipher.exe")
endif()

set(_batch_path "${_work_dir}/build-sqlcipher.cmd")
file(TO_NATIVE_PATH "${_batch_path}" _batch_native)
file(WRITE "${_batch_path}"
    "@echo off\n"
    "setlocal EnableExtensions DisableDelayedExpansion\n"
    "chcp.com 65001 >nul\n"
    "set \"VSCMD_SKIP_SENDTELEMETRY=1\"\n"
    "set \"LC_ALL=C\"\n"
    "set \"LANG=C\"\n"
    "set \"LANGUAGE=\"\n"
    "call \"${_vs_devcmd_native}\" -no_logo -arch=x64 -host_arch=x64 -winsdk=${SQLCIPHER_WINDOWS_SDK_VERSION}\n"
    "if errorlevel 1 exit /b 1\n"
    "if /i not \"%VSCMD_ARG_HOST_ARCH%\"==\"x64\" exit /b 1\n"
    "if /i not \"%VSCMD_ARG_TGT_ARCH%\"==\"x64\" exit /b 1\n"
    "if /i not \"%WindowsSDKVersion%\"==\"${SQLCIPHER_WINDOWS_SDK_VERSION}\\\" exit /b 1\n"
    "where.exe cl.exe >nul 2>&1 || exit /b 1\n"
    "where.exe nmake.exe >nul 2>&1 || exit /b 1\n"
    "where.exe dumpbin.exe >nul 2>&1 || exit /b 1\n"
    "set \"PATH=${_openssl_native}\\bin;%PATH%\"\n"
    "pushd \"${_work_native}\" || exit /b 1\n"
    "nmake /nologo /f \"${_source_native}\\Makefile.msc\" ^\n"
    "  TOP=${_source_native} ^\n"
    "  PLATFORM=x64 ^\n"
    "  USE_AMALGAMATION=1 ^\n"
    "  USE_CRT_DLL=1 ^\n"
    "  NO_TCL=1 ^\n"
    "  DYNAMIC_SHELL=1 ^\n"
    "  DEBUG=${_debug_level} ^\n"
    "  SQLITE3DLL=sqlcipher.dll ^\n"
    "  SQLITE3LIB=sqlcipher.lib ^\n"
    "  SQLITE3EXE=sqlcipher.exe ^\n"
    "  \"TCCOPTS=-I${_openssl_native}\\include\" ^\n"
    "  \"LTLIBPATHS=/LIBPATH:${_openssl_native}\\lib\" ^\n"
    "  \"CORE_LINK_OPTS=/EXPORT:sqlcipher_version\" ^\n"
    "  \"LDFLAGS=${_nmake_ldflags}\" ^\n"
    "  \"LTLIBS=libcrypto.lib\" ^\n"
    "  \"OPTS=${SQLCIPHER_DEFINITIONS}\" ^\n"
    "  clean ${_targets}\n"
    "if errorlevel 1 (popd & exit /b 1)\n"
    "dumpbin /dependents sqlcipher.dll > sqlcipher-dependents.txt\n"
    "if errorlevel 1 (popd & exit /b 1)\n"
    "findstr /i /c:\"libcrypto-3-x64.dll\" sqlcipher-dependents.txt >nul\n"
    "if errorlevel 1 (echo ERROR: SQLCipher does not depend on libcrypto-3-x64.dll. & popd & exit /b 1)\n"
)

if(SQLCIPHER_CONFIGURATION STREQUAL "Release")
    file(APPEND "${_batch_path}"
        "findstr /i /c:\"VCRUNTIME140D.dll\" /c:\"VCRUNTIME140_1D.dll\" /c:\"ucrtbased.dll\" sqlcipher-dependents.txt >nul\n"
        "if not errorlevel 1 (echo ERROR: Release SQLCipher depends on the Debug CRT. & popd & exit /b 1)\n"
    )
else()
    file(APPEND "${_batch_path}"
        "findstr /i /c:\"VCRUNTIME140D.dll\" /c:\"VCRUNTIME140_1D.dll\" /c:\"ucrtbased.dll\" sqlcipher-dependents.txt >nul\n"
        "if errorlevel 1 (echo ERROR: Debug SQLCipher does not depend on the Debug CRT. & popd & exit /b 1)\n"
    )
endif()
file(APPEND "${_batch_path}" "popd\nexit /b 0\n")

find_program(_powershell_executable NAMES powershell.exe REQUIRED)
string(REPLACE "'" "''" _batch_powershell "${_batch_native}")
execute_process(
    COMMAND "${_powershell_executable}"
        -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass
        -Command "& '${_batch_powershell}'; exit $LASTEXITCODE"
    RESULT_VARIABLE _build_result
    COMMAND_ECHO STDOUT
    ENCODING UTF8
)
if(NOT _build_result EQUAL 0)
    message(FATAL_ERROR "SQLCipher ${SQLCIPHER_CONFIGURATION} NMake build failed.")
endif()

function(_copy_required _source _destination)
    if(NOT EXISTS "${_source}")
        message(FATAL_ERROR "Expected SQLCipher artifact is missing: ${_source}")
    endif()
    file(COPY_FILE "${_source}" "${_destination}" ONLY_IF_DIFFERENT)
endfunction()

_copy_required("${_work_dir}/sqlcipher.dll" "${_stage_bin}/sqlcipher.dll")
_copy_required("${_work_dir}/sqlcipher.lib" "${_stage_lib}/sqlcipher.lib")
_copy_required("${_work_dir}/sqlite3.h" "${_stage_include}/sqlite3.h")
_copy_required("${_work_dir}/sqlite3ext.h" "${_stage_include}/sqlite3ext.h")
_copy_required("${_work_dir}/sqlite3session.h" "${_stage_include}/sqlite3session.h")
if(SQLCIPHER_BUILD_CLI)
    _copy_required("${_work_dir}/sqlcipher.exe" "${_stage_bin}/sqlcipher.exe")
endif()

file(GLOB _pdb_files "${_work_dir}/*.pdb")
foreach(_pdb IN LISTS _pdb_files)
    get_filename_component(_pdb_name "${_pdb}" NAME)
    file(COPY_FILE "${_pdb}" "${_stage_pdb}/${_pdb_name}" ONLY_IF_DIFFERENT)
endforeach()

set(_provider_probe "Not run because SQLCIPHER_BUILD_CLI=OFF")
if(SQLCIPHER_BUILD_CLI)
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env
            "PATH=${_openssl_root}/bin;$ENV{PATH}"
            "${_stage_bin}/sqlcipher.exe" :memory:
            "PRAGMA key='provider-probe'; PRAGMA cipher_version; PRAGMA cipher_provider; PRAGMA cipher_provider_version;"
        RESULT_VARIABLE _probe_result
        OUTPUT_VARIABLE _provider_probe
        ERROR_VARIABLE _probe_error
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(NOT _probe_result EQUAL 0)
        message(FATAL_ERROR "Staged sqlcipher.exe provider probe failed: ${_probe_error}")
    endif()
    if(NOT _provider_probe MATCHES "4\\.18\\.0"
       OR NOT _provider_probe MATCHES "openssl"
       OR NOT _provider_probe MATCHES "OpenSSL 3\\.5\\.7")
        message(FATAL_ERROR "Unexpected SQLCipher provider probe output:\n${_provider_probe}")
    endif()
endif()

file(SHA256 "${_stage_bin}/sqlcipher.dll" _sqlcipher_dll_sha256)
file(SHA256 "${_stage_lib}/sqlcipher.lib" _sqlcipher_lib_sha256)
file(SHA256 "${_openssl_root}/bin/libcrypto-3-x64.dll" _libcrypto_sha256)

set(_manifest "${_stage_dir}/build-manifest.txt")
file(WRITE "${_manifest}"
    "SQLCipher build manifest\n"
    "========================\n"
    "SQLCipher tag: ${SQLCIPHER_EXPECTED_TAG}\n"
    "SQLCipher commit: ${_actual_commit}\n"
    "Configuration: ${SQLCIPHER_CONFIGURATION}\n"
    "Architecture: x64\n"
    "Visual Studio: ${SQLCIPHER_VS_EDITION} 2022\n"
    "Windows SDK: ${SQLCIPHER_WINDOWS_SDK_VERSION}\n"
    "CRT: ${_crt}\n"
    "OpenSSL stage: ${_openssl_root}\n"
    "Definitions: ${SQLCIPHER_DEFINITIONS}\n"
    "SQLCipher tests: not run by the product build wrapper\n"
    "sqlcipher.dll SHA256: ${_sqlcipher_dll_sha256}\n"
    "sqlcipher.lib SHA256: ${_sqlcipher_lib_sha256}\n"
    "libcrypto-3-x64.dll SHA256: ${_libcrypto_sha256}\n"
    "Provider probe:\n${_provider_probe}\n"
)

message(STATUS "SQLCipher ${SQLCIPHER_CONFIGURATION} stage: ${_stage_dir}")
message(STATUS "SQLCipher manifest: ${_manifest}")
