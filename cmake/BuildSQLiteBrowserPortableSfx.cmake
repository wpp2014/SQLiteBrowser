cmake_minimum_required(VERSION 3.30.3)

foreach(_required_variable IN ITEMS
        SQLITEBROWSER_SFX_SOURCE_DIR
        SQLITEBROWSER_SFX_CONFIGURATION_ROOT
        SQLITEBROWSER_SFX_RUNTIME_DIR
        SQLITEBROWSER_SFX_RUNTIME_MANIFEST
        SQLITEBROWSER_SFX_VERSION
        SQLITEBROWSER_SFX_APP_NAME
        SQLITEBROWSER_SFX_SMOKE_EXECUTABLE
        SQLITEBROWSER_SFX_TLS_URL
        SQLITEBROWSER_SFX_NSIS_SCRIPT
        SQLITEBROWSER_SFX_ARTIFACT_DIR
        SQLITEBROWSER_SFX_WORK_DIR
        SQLITEBROWSER_SFX_VERIFY_DIR)
    if(NOT DEFINED ${_required_variable}
            OR "${${_required_variable}}" STREQUAL "")
        message(FATAL_ERROR "Missing required SFX variable: ${_required_variable}")
    endif()
endforeach()

if(NOT SQLITEBROWSER_SFX_VERSION MATCHES "^[0-9]+\.[0-9]+\.[0-9]+$")
    message(FATAL_ERROR
        "SFX version must contain exactly three numeric fields: "
        "${SQLITEBROWSER_SFX_VERSION}")
endif()

foreach(_path_variable IN ITEMS
        SQLITEBROWSER_SFX_SOURCE_DIR
        SQLITEBROWSER_SFX_CONFIGURATION_ROOT
        SQLITEBROWSER_SFX_RUNTIME_DIR
        SQLITEBROWSER_SFX_RUNTIME_MANIFEST
        SQLITEBROWSER_SFX_SMOKE_EXECUTABLE
        SQLITEBROWSER_SFX_NSIS_SCRIPT
        SQLITEBROWSER_SFX_ARTIFACT_DIR
        SQLITEBROWSER_SFX_WORK_DIR
        SQLITEBROWSER_SFX_VERIFY_DIR)
    cmake_path(ABSOLUTE_PATH ${_path_variable} NORMALIZE
        OUTPUT_VARIABLE _normalized_path)
    set(${_path_variable} "${_normalized_path}")
endforeach()

set(_expected_runtime_dir
    "${SQLITEBROWSER_SFX_CONFIGURATION_ROOT}/package/runtime")
set(_expected_manifest
    "${SQLITEBROWSER_SFX_CONFIGURATION_ROOT}/package/metadata/runtime-manifest.txt")
set(_expected_artifact_dir
    "${SQLITEBROWSER_SFX_CONFIGURATION_ROOT}/package/artifacts")
set(_expected_work_dir
    "${SQLITEBROWSER_SFX_CONFIGURATION_ROOT}/package/build/nsis-portable")
set(_expected_verify_dir
    "${SQLITEBROWSER_SFX_CONFIGURATION_ROOT}/package/verify/portable-sfx")
set(_expected_nsis_script
    "${SQLITEBROWSER_SFX_SOURCE_DIR}/installer/windows/nsis/portable-sfx.nsi")
foreach(_expected_path_variable IN ITEMS
        _expected_runtime_dir _expected_manifest _expected_artifact_dir
        _expected_work_dir _expected_verify_dir _expected_nsis_script)
    cmake_path(NORMAL_PATH ${_expected_path_variable})
endforeach()

foreach(_path_pair IN ITEMS
        "SQLITEBROWSER_SFX_RUNTIME_DIR;_expected_runtime_dir"
        "SQLITEBROWSER_SFX_RUNTIME_MANIFEST;_expected_manifest"
        "SQLITEBROWSER_SFX_ARTIFACT_DIR;_expected_artifact_dir"
        "SQLITEBROWSER_SFX_WORK_DIR;_expected_work_dir"
        "SQLITEBROWSER_SFX_VERIFY_DIR;_expected_verify_dir"
        "SQLITEBROWSER_SFX_NSIS_SCRIPT;_expected_nsis_script")
    list(GET _path_pair 0 _actual_variable)
    list(GET _path_pair 1 _expected_variable)
    cmake_path(COMPARE
        "${${_actual_variable}}" EQUAL "${${_expected_variable}}" _matches)
    if(NOT _matches)
        message(FATAL_ERROR
            "Unsafe SFX path for ${_actual_variable}.\n"
            "Expected: ${${_expected_variable}}\n"
            "Actual:   ${${_actual_variable}}")
    endif()
endforeach()

cmake_path(GET SQLITEBROWSER_SFX_CONFIGURATION_ROOT FILENAME _root_name)
cmake_path(GET SQLITEBROWSER_SFX_CONFIGURATION_ROOT PARENT_PATH _output_dir)
cmake_path(GET _output_dir FILENAME _output_name)
if(NOT _root_name STREQUAL "x64-shared-release"
        OR NOT _output_name STREQUAL "output")
    message(FATAL_ERROR
        "Portable SFX packaging is restricted to output/x64-shared-release; "
        "actual: ${SQLITEBROWSER_SFX_CONFIGURATION_ROOT}")
endif()

foreach(_required_file IN ITEMS
        "${SQLITEBROWSER_SFX_RUNTIME_MANIFEST}"
        "${SQLITEBROWSER_SFX_SMOKE_EXECUTABLE}"
        "${SQLITEBROWSER_SFX_NSIS_SCRIPT}"
        "${SQLITEBROWSER_SFX_SOURCE_DIR}/src/iconwin.ico")
    if(NOT EXISTS "${_required_file}")
        message(FATAL_ERROR "Required SFX input is missing: ${_required_file}")
    endif()
endforeach()
if(NOT IS_DIRECTORY "${SQLITEBROWSER_SFX_RUNTIME_DIR}")
    message(FATAL_ERROR
        "Release package runtime is missing: ${SQLITEBROWSER_SFX_RUNTIME_DIR}")
endif()

set(_makensis "C:/Program Files (x86)/NSIS/makensis.exe")
if(NOT EXISTS "${_makensis}")
    message(FATAL_ERROR
        "NSIS 3.12 was not found at the required default path: ${_makensis}")
endif()
execute_process(
    COMMAND "${_makensis}" /VERSION
    RESULT_VARIABLE _nsis_version_result
    OUTPUT_VARIABLE _nsis_version
    ERROR_VARIABLE _nsis_version_error
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_STRIP_TRAILING_WHITESPACE)
if(NOT _nsis_version_result EQUAL 0)
    message(FATAL_ERROR
        "Failed to query NSIS version: ${_nsis_version_error}")
endif()
if(NOT _nsis_version STREQUAL "v3.12")
    message(FATAL_ERROR
        "Portable SFX requires NSIS v3.12; actual: ${_nsis_version}")
endif()

file(READ "${SQLITEBROWSER_SFX_NSIS_SCRIPT}" _nsis_source)
foreach(_required_pattern IN ITEMS
        "RequestExecutionLevel[ \t]+user"
        "CRCCheck[ \t]+force"
        "Unicode[ \t]+true"
        "File[ \t]+/r")
    if(NOT _nsis_source MATCHES "${_required_pattern}")
        message(FATAL_ERROR
            "Portable SFX script is missing required policy: ${_required_pattern}")
    endif()
endforeach()
foreach(_forbidden_pattern IN ITEMS
        "RequestExecutionLevel[ \t]+admin"
        "WriteReg(Str|DWORD|ExpandStr|Bin)"
        "DeleteReg(Key|Value)"
        "WriteUninstaller"
        "CreateShortCut"
        "Exec(Wait|Shell)?[ \t]+.*msiexec")
    if(_nsis_source MATCHES "${_forbidden_pattern}")
        message(FATAL_ERROR
            "Portable SFX script contains forbidden behavior: ${_forbidden_pattern}")
    endif()
endforeach()

include("${SQLITEBROWSER_SFX_SOURCE_DIR}/cmake/SQLiteBrowserWindowsRuntime.cmake")

function(_sqlitebrowser_sfx_validate_manifest runtime_dir manifest output_paths)
    file(STRINGS "${manifest}" _manifest_lines ENCODING UTF-8)
    list(FIND _manifest_lines "Configuration: Release" _release_header)
    list(FIND _manifest_lines "Architecture: x64" _architecture_header)
    list(FIND _manifest_lines "Runtime policy: strict allowlist" _policy_header)
    list(FIND _manifest_lines "Files:" _files_header)
    if(_release_header EQUAL -1 OR _architecture_header EQUAL -1
            OR _policy_header EQUAL -1 OR _files_header EQUAL -1)
        message(FATAL_ERROR
            "The runtime manifest is missing required Release x64 headers.")
    endif()

    set(_manifest_paths)
    math(EXPR _first_file_line "${_files_header} + 1")
    list(LENGTH _manifest_lines _manifest_line_count)
    if(_first_file_line GREATER_EQUAL _manifest_line_count)
        message(FATAL_ERROR "The runtime manifest contains no files.")
    endif()
    math(EXPR _last_file_line "${_manifest_line_count} - 1")
    foreach(_line_index RANGE ${_first_file_line} ${_last_file_line})
        list(GET _manifest_lines ${_line_index} _manifest_line)
        if(NOT _manifest_line MATCHES "^([0-9A-Fa-f]+)\t(.+)$")
            message(FATAL_ERROR "Malformed runtime manifest line: ${_manifest_line}")
        endif()
        set(_expected_hash "${CMAKE_MATCH_1}")
        string(TOLOWER "${_expected_hash}" _expected_hash)
        string(LENGTH "${_expected_hash}" _hash_length)
        if(NOT _hash_length EQUAL 64)
            message(FATAL_ERROR "Invalid SHA-256 in manifest: ${_manifest_line}")
        endif()
        set(_relative_path "${CMAKE_MATCH_2}")
        string(REPLACE "\\" "/" _relative_path "${_relative_path}")
        if(IS_ABSOLUTE "${_relative_path}"
                OR _relative_path MATCHES "(^|/)\.\.(/|$)")
            message(FATAL_ERROR "Unsafe runtime manifest path: ${_relative_path}")
        endif()
        list(FIND _manifest_paths "${_relative_path}" _duplicate_index)
        if(NOT _duplicate_index EQUAL -1)
            message(FATAL_ERROR
                "Duplicate runtime manifest path: ${_relative_path}")
        endif()
        set(_runtime_file "${runtime_dir}/${_relative_path}")
        if(NOT EXISTS "${_runtime_file}" OR IS_DIRECTORY "${_runtime_file}")
            message(FATAL_ERROR "Manifest file is missing: ${_relative_path}")
        endif()
        file(SHA256 "${_runtime_file}" _actual_hash)
        string(TOLOWER "${_actual_hash}" _actual_hash)
        if(NOT _actual_hash STREQUAL _expected_hash)
            message(FATAL_ERROR "Manifest hash mismatch: ${_relative_path}")
        endif()
        list(APPEND _manifest_paths "${_relative_path}")
    endforeach()

    file(GLOB_RECURSE _actual_paths
        LIST_DIRECTORIES FALSE
        RELATIVE "${runtime_dir}"
        "${runtime_dir}/*")
    set(_normalized_actual_paths)
    foreach(_actual_path IN LISTS _actual_paths)
        string(REPLACE "\\" "/" _actual_path "${_actual_path}")
        list(APPEND _normalized_actual_paths "${_actual_path}")
    endforeach()
    list(SORT _normalized_actual_paths)
    set(_sorted_manifest_paths "${_manifest_paths}")
    list(SORT _sorted_manifest_paths)
    if(NOT _normalized_actual_paths STREQUAL _sorted_manifest_paths)
        message(FATAL_ERROR
            "Runtime files no longer match runtime-manifest.txt: ${runtime_dir}")
    endif()

    set(${output_paths} "${_manifest_paths}" PARENT_SCOPE)
endfunction()

_sqlitebrowser_validate_runtime(
    "${SQLITEBROWSER_SFX_RUNTIME_DIR}" Release PACKAGE
    "${SQLITEBROWSER_SFX_APP_NAME}")
_sqlitebrowser_sfx_validate_manifest(
    "${SQLITEBROWSER_SFX_RUNTIME_DIR}"
    "${SQLITEBROWSER_SFX_RUNTIME_MANIFEST}"
    _manifest_paths)

if(EXISTS "${SQLITEBROWSER_SFX_RUNTIME_DIR}/vc_redist.x64.exe")
    message(WARNING
        "The current runtime still contains vc_redist.x64.exe. The portable "
        "SFX will carry it as an ordinary file and will not execute it. "
        "Replace this with an app-local VC143 runtime before release.")
endif()

set(_artifact_base
    "DB.Browser.for.SQLCipher-${SQLITEBROWSER_SFX_VERSION}-win-x64-portable")
set(_sfx_path "${SQLITEBROWSER_SFX_ARTIFACT_DIR}/${_artifact_base}.exe")
set(_sfx_checksum_path "${_sfx_path}.sha256")
set(_temporary_sfx "${SQLITEBROWSER_SFX_WORK_DIR}/${_artifact_base}.exe.next")
set(_positive_root "${SQLITEBROWSER_SFX_VERIFY_DIR}/SQLite Browser 验证")
set(_negative_root "${SQLITEBROWSER_SFX_VERIFY_DIR}/non-empty-target")
set(_negative_sentinel "${_negative_root}/do-not-overwrite.txt")

file(REMOVE_RECURSE
    "${SQLITEBROWSER_SFX_WORK_DIR}"
    "${SQLITEBROWSER_SFX_VERIFY_DIR}")
file(MAKE_DIRECTORY
    "${SQLITEBROWSER_SFX_WORK_DIR}"
    "${SQLITEBROWSER_SFX_ARTIFACT_DIR}"
    "${SQLITEBROWSER_SFX_VERIFY_DIR}")

cmake_path(NATIVE_PATH SQLITEBROWSER_SFX_RUNTIME_DIR NORMALIZE
    _runtime_native)
cmake_path(NATIVE_PATH _temporary_sfx NORMALIZE _temporary_sfx_native)
set(_icon_file "${SQLITEBROWSER_SFX_SOURCE_DIR}/src/iconwin.ico")
cmake_path(NATIVE_PATH _icon_file NORMALIZE _icon_native)
cmake_path(NATIVE_PATH SQLITEBROWSER_SFX_NSIS_SCRIPT NORMALIZE
    _nsis_script_native)

execute_process(
    COMMAND "${_makensis}" /V4
        "/DPRODUCT_VERSION=${SQLITEBROWSER_SFX_VERSION}"
        "/DPAYLOAD_DIR=${_runtime_native}"
        "/DOUTPUT_FILE=${_temporary_sfx_native}"
        "/DICON_FILE=${_icon_native}"
        "${_nsis_script_native}"
    RESULT_VARIABLE _makensis_result
    COMMAND_ECHO STDOUT
    ECHO_OUTPUT_VARIABLE
    ECHO_ERROR_VARIABLE)
if(NOT _makensis_result EQUAL 0 OR NOT EXISTS "${_temporary_sfx}")
    message(FATAL_ERROR
        "NSIS portable SFX build failed with exit code ${_makensis_result}.")
endif()

file(REMOVE "${_sfx_path}" "${_sfx_checksum_path}")
file(RENAME "${_temporary_sfx}" "${_sfx_path}" RESULT _publish_result)
if(NOT _publish_result STREQUAL "0")
    message(FATAL_ERROR "Failed to publish portable SFX: ${_publish_result}")
endif()

function(_sqlitebrowser_run_sfx_silent sfx_path target_dir runner_name result_var)
    cmake_path(NATIVE_PATH sfx_path NORMALIZE _sfx_native)
    cmake_path(NATIVE_PATH target_dir NORMALIZE _target_native)
    set(_runner "${SQLITEBROWSER_SFX_WORK_DIR}/${runner_name}.cmd")
    file(WRITE "${_runner}"
        "@echo off\r\n"
        "chcp 65001 >nul\r\n"
        "\"${_sfx_native}\" /S /D=${_target_native}\r\n"
        "exit /b %ERRORLEVEL%\r\n")
    cmake_path(NATIVE_PATH _runner NORMALIZE _runner_native)
    execute_process(
        COMMAND "$ENV{ComSpec}" /d /c call "${_runner_native}"
        RESULT_VARIABLE _runner_result
        COMMAND_ECHO STDOUT)
    set(${result_var} "${_runner_result}" PARENT_SCOPE)
endfunction()

_sqlitebrowser_run_sfx_silent(
    "${_sfx_path}" "${_positive_root}" run-positive _extract_result)
if(NOT _extract_result EQUAL 0)
    message(FATAL_ERROR
        "Portable SFX silent extraction failed with exit code ${_extract_result}.")
endif()

_sqlitebrowser_validate_runtime(
    "${_positive_root}" Release PACKAGE "${SQLITEBROWSER_SFX_APP_NAME}")
_sqlitebrowser_sfx_validate_manifest(
    "${_positive_root}" "${SQLITEBROWSER_SFX_RUNTIME_MANIFEST}"
    _extracted_manifest_paths)

set(_extracted_smoke
    "${_positive_root}/sqlitebrowser-runtime-smoke-tool.exe")
file(COPY_FILE
    "${SQLITEBROWSER_SFX_SMOKE_EXECUTABLE}"
    "${_extracted_smoke}"
    ONLY_IF_DIFFERENT
    RESULT _smoke_copy_result)
if(NOT _smoke_copy_result STREQUAL "0")
    message(FATAL_ERROR
        "Failed to place the temporary portable runtime smoke tool: "
        "${_smoke_copy_result}")
endif()

# Run the helper from the extracted application directory. This mirrors the
# packaged application's Windows DLL search layout and keeps Qt/OpenSSL loading
# reliable when the selected directory contains non-ASCII characters.
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DAPP_EXECUTABLE=${_positive_root}/${SQLITEBROWSER_SFX_APP_NAME}"
        "-DSMOKE_EXECUTABLE=${_extracted_smoke}"
        "-DRUNTIME_DIR=${_positive_root}"
        "-DSMOKE_WORK_DIR=${SQLITEBROWSER_SFX_WORK_DIR}/smoke"
        "-DTLS_URL=${SQLITEBROWSER_SFX_TLS_URL}"
        -P "${SQLITEBROWSER_SFX_SOURCE_DIR}/cmake/RunSQLiteBrowserWindowsSmoke.cmake"
    RESULT_VARIABLE _smoke_result
    COMMAND_ECHO STDOUT)
file(REMOVE "${_extracted_smoke}")
if(NOT _smoke_result EQUAL 0)
    message(FATAL_ERROR
        "Extracted portable SFX runtime smoke failed with exit code "
        "${_smoke_result}.")
endif()
_sqlitebrowser_sfx_validate_manifest(
    "${_positive_root}" "${SQLITEBROWSER_SFX_RUNTIME_MANIFEST}"
    _extracted_manifest_paths_after_smoke)

file(MAKE_DIRECTORY "${_negative_root}")
file(WRITE "${_negative_sentinel}" "sentinel-do-not-overwrite\n")
file(SHA256 "${_negative_sentinel}" _sentinel_hash_before)
_sqlitebrowser_run_sfx_silent(
    "${_sfx_path}" "${_negative_root}" run-negative _negative_result)
if(NOT _negative_result EQUAL 25)
    message(FATAL_ERROR
        "Portable SFX non-empty target test returned ${_negative_result}; "
        "expected stable validation exit code 25.")
endif()
file(GLOB_RECURSE _negative_files
    LIST_DIRECTORIES FALSE
    RELATIVE "${_negative_root}"
    "${_negative_root}/*")
if(NOT _negative_files STREQUAL "do-not-overwrite.txt")
    message(FATAL_ERROR
        "Portable SFX changed the non-empty negative-test directory: "
        "${_negative_files}")
endif()
file(SHA256 "${_negative_sentinel}" _sentinel_hash_after)
if(NOT _sentinel_hash_after STREQUAL _sentinel_hash_before)
    message(FATAL_ERROR
        "Portable SFX modified the negative-test sentinel file.")
endif()

file(SHA256 "${_sfx_path}" _sfx_hash)
string(TOLOWER "${_sfx_hash}" _sfx_hash)
file(SIZE "${_sfx_path}" _sfx_size)
file(WRITE "${_sfx_checksum_path}"
    "${_sfx_hash}  ${_artifact_base}.exe\n")

execute_process(
    COMMAND git -C "${SQLITEBROWSER_SFX_SOURCE_DIR}" rev-parse HEAD
    OUTPUT_VARIABLE _git_commit
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
if(_git_commit STREQUAL "")
    set(_git_commit "Unknown")
endif()
string(CONCAT _sfx_manifest
    "SQLiteBrowser Windows portable SFX manifest\n"
    "Format version: 1\n"
    "Version: ${SQLITEBROWSER_SFX_VERSION}\n"
    "Architecture: x64\n"
    "Configuration: Release\n"
    "NSIS: ${_nsis_version}\n"
    "Git commit: ${_git_commit}\n"
    "Payload manifest: package/metadata/runtime-manifest.txt\n"
    "SFX: ${_artifact_base}.exe\n"
    "SFX size: ${_sfx_size}\n"
    "SFX SHA-256: ${_sfx_hash}\n"
    "Silent extraction: passed\n"
    "Non-empty target rejection: passed (exit code: 25)\n")
file(WRITE
    "${SQLITEBROWSER_SFX_CONFIGURATION_ROOT}/package/metadata/portable-sfx-manifest.txt"
    "${_sfx_manifest}")

message(STATUS "SQLiteBrowser portable SFX verified: ${_sfx_path}")
message(STATUS "SQLiteBrowser portable SFX SHA-256: ${_sfx_hash}")
