cmake_minimum_required(VERSION 3.30.3)

foreach(_required_variable IN ITEMS
        SQLITEBROWSER_MSI_SOURCE_DIR
        SQLITEBROWSER_MSI_CONFIGURATION_ROOT
        SQLITEBROWSER_MSI_RUNTIME_DIR
        SQLITEBROWSER_MSI_RUNTIME_MANIFEST
        SQLITEBROWSER_MSI_WIX_PROJECT
        SQLITEBROWSER_MSI_MSBUILD
        SQLITEBROWSER_MSI_WIX_VERSION
        SQLITEBROWSER_MSI_VERSION
        SQLITEBROWSER_MSI_PRODUCT_NAME
        SQLITEBROWSER_MSI_MANUFACTURER
        SQLITEBROWSER_MSI_UPGRADE_CODE
        SQLITEBROWSER_MSI_APP_NAME
        SQLITEBROWSER_MSI_ARTIFACT_DIR
        SQLITEBROWSER_MSI_WORK_DIR
        SQLITEBROWSER_MSI_VERIFY_DIR)
    if(NOT DEFINED ${_required_variable}
            OR "${${_required_variable}}" STREQUAL "")
        message(FATAL_ERROR "Missing required MSI variable: ${_required_variable}")
    endif()
endforeach()

if(NOT SQLITEBROWSER_MSI_VERSION MATCHES "^[0-9]+\.[0-9]+\.[0-9]+$")
    message(FATAL_ERROR
        "MSI version must contain exactly three numeric fields: "
        "${SQLITEBROWSER_MSI_VERSION}")
endif()
if(NOT SQLITEBROWSER_MSI_WIX_VERSION MATCHES "^[0-9]+\.[0-9]+\.[0-9]+$")
    message(FATAL_ERROR
        "WiX SDK version must be exact: ${SQLITEBROWSER_MSI_WIX_VERSION}")
endif()
set(_upgrade_code_compact "${SQLITEBROWSER_MSI_UPGRADE_CODE}")
string(REPLACE "{" "" _upgrade_code_compact "${_upgrade_code_compact}")
string(REPLACE "}" "" _upgrade_code_compact "${_upgrade_code_compact}")
string(REPLACE "-" "" _upgrade_code_compact "${_upgrade_code_compact}")
string(LENGTH "${_upgrade_code_compact}" _upgrade_code_length)
if(NOT _upgrade_code_length EQUAL 32
        OR NOT _upgrade_code_compact MATCHES "^[0-9A-Fa-f]+$")
    message(FATAL_ERROR
        "Invalid MSI UpgradeCode: ${SQLITEBROWSER_MSI_UPGRADE_CODE}")
endif()

foreach(_path_variable IN ITEMS
        SQLITEBROWSER_MSI_SOURCE_DIR
        SQLITEBROWSER_MSI_CONFIGURATION_ROOT
        SQLITEBROWSER_MSI_RUNTIME_DIR
        SQLITEBROWSER_MSI_RUNTIME_MANIFEST
        SQLITEBROWSER_MSI_WIX_PROJECT
        SQLITEBROWSER_MSI_MSBUILD
        SQLITEBROWSER_MSI_ARTIFACT_DIR
        SQLITEBROWSER_MSI_WORK_DIR
        SQLITEBROWSER_MSI_VERIFY_DIR)
    cmake_path(ABSOLUTE_PATH ${_path_variable} NORMALIZE
        OUTPUT_VARIABLE _normalized_path)
    set(${_path_variable} "${_normalized_path}")
endforeach()

set(_expected_runtime_dir
    "${SQLITEBROWSER_MSI_CONFIGURATION_ROOT}/package/runtime")
set(_expected_manifest
    "${SQLITEBROWSER_MSI_CONFIGURATION_ROOT}/package/metadata/runtime-manifest.txt")
set(_expected_artifact_dir
    "${SQLITEBROWSER_MSI_CONFIGURATION_ROOT}/package/artifacts")
set(_expected_work_dir
    "${SQLITEBROWSER_MSI_CONFIGURATION_ROOT}/package/build/wix")
set(_expected_verify_dir
    "${SQLITEBROWSER_MSI_CONFIGURATION_ROOT}/package/verify/msi-admin-image")
foreach(_expected_path_variable IN ITEMS
        _expected_runtime_dir _expected_manifest _expected_artifact_dir
        _expected_work_dir _expected_verify_dir)
    cmake_path(NORMAL_PATH ${_expected_path_variable})
endforeach()

foreach(_path_pair IN ITEMS
        "SQLITEBROWSER_MSI_RUNTIME_DIR;_expected_runtime_dir"
        "SQLITEBROWSER_MSI_RUNTIME_MANIFEST;_expected_manifest"
        "SQLITEBROWSER_MSI_ARTIFACT_DIR;_expected_artifact_dir"
        "SQLITEBROWSER_MSI_WORK_DIR;_expected_work_dir"
        "SQLITEBROWSER_MSI_VERIFY_DIR;_expected_verify_dir")
    list(GET _path_pair 0 _actual_variable)
    list(GET _path_pair 1 _expected_variable)
    cmake_path(COMPARE
        "${${_actual_variable}}" EQUAL "${${_expected_variable}}" _matches)
    if(NOT _matches)
        message(FATAL_ERROR
            "Unsafe MSI path for ${_actual_variable}.\n"
            "Expected: ${${_expected_variable}}\n"
            "Actual:   ${${_actual_variable}}")
    endif()
endforeach()

cmake_path(GET SQLITEBROWSER_MSI_CONFIGURATION_ROOT FILENAME _root_name)
cmake_path(GET SQLITEBROWSER_MSI_CONFIGURATION_ROOT PARENT_PATH _output_dir)
cmake_path(GET _output_dir FILENAME _output_name)
if(NOT _root_name STREQUAL "x64-shared-release"
        OR NOT _output_name STREQUAL "output")
    message(FATAL_ERROR
        "MSI packaging is restricted to output/x64-shared-release; actual: "
        "${SQLITEBROWSER_MSI_CONFIGURATION_ROOT}")
endif()

if(NOT EXISTS "${SQLITEBROWSER_MSI_MSBUILD}")
    message(FATAL_ERROR
        "Visual Studio 2022 MSBuild was not found: ${SQLITEBROWSER_MSI_MSBUILD}")
endif()
if(NOT EXISTS "${SQLITEBROWSER_MSI_WIX_PROJECT}")
    message(FATAL_ERROR
        "WiX project was not found: ${SQLITEBROWSER_MSI_WIX_PROJECT}")
endif()
if(NOT IS_DIRECTORY "${SQLITEBROWSER_MSI_RUNTIME_DIR}")
    message(FATAL_ERROR
        "Release package runtime is missing: ${SQLITEBROWSER_MSI_RUNTIME_DIR}")
endif()
if(NOT EXISTS "${SQLITEBROWSER_MSI_RUNTIME_MANIFEST}")
    message(FATAL_ERROR
        "Release runtime manifest is missing: ${SQLITEBROWSER_MSI_RUNTIME_MANIFEST}")
endif()

include("${SQLITEBROWSER_MSI_SOURCE_DIR}/cmake/SQLiteBrowserWindowsRuntime.cmake")
_sqlitebrowser_validate_runtime(
    "${SQLITEBROWSER_MSI_RUNTIME_DIR}"
    Release PACKAGE "${SQLITEBROWSER_MSI_APP_NAME}")

file(STRINGS "${SQLITEBROWSER_MSI_RUNTIME_MANIFEST}" _manifest_lines
    ENCODING UTF-8)
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
set(_manifest_hashes)
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
        message(FATAL_ERROR "Duplicate runtime manifest path: ${_relative_path}")
    endif()
    set(_runtime_file "${SQLITEBROWSER_MSI_RUNTIME_DIR}/${_relative_path}")
    if(NOT EXISTS "${_runtime_file}" OR IS_DIRECTORY "${_runtime_file}")
        message(FATAL_ERROR "Manifest file is missing: ${_relative_path}")
    endif()
    file(SHA256 "${_runtime_file}" _actual_hash)
    string(TOLOWER "${_actual_hash}" _actual_hash)
    if(NOT _actual_hash STREQUAL _expected_hash)
        message(FATAL_ERROR "Manifest hash mismatch: ${_relative_path}")
    endif()
    list(APPEND _manifest_paths "${_relative_path}")
    list(APPEND _manifest_hashes "${_expected_hash}")
endforeach()

file(GLOB_RECURSE _actual_paths
    LIST_DIRECTORIES FALSE
    RELATIVE "${SQLITEBROWSER_MSI_RUNTIME_DIR}"
    "${SQLITEBROWSER_MSI_RUNTIME_DIR}/*")
set(_normalized_actual_paths)
foreach(_actual_path IN LISTS _actual_paths)
    string(REPLACE "\\" "/" _actual_path "${_actual_path}")
    list(APPEND _normalized_actual_paths "${_actual_path}")
endforeach()
set(_actual_paths "${_normalized_actual_paths}")
list(SORT _actual_paths)
set(_sorted_manifest_paths "${_manifest_paths}")
list(SORT _sorted_manifest_paths)
if(NOT _actual_paths STREQUAL _sorted_manifest_paths)
    message(FATAL_ERROR
        "Release runtime files no longer match runtime-manifest.txt.")
endif()

file(MAKE_DIRECTORY
    "${SQLITEBROWSER_MSI_ARTIFACT_DIR}"
    "${SQLITEBROWSER_MSI_WORK_DIR}")
set(_artifact_base
    "DB.Browser.for.SQLCipher-${SQLITEBROWSER_MSI_VERSION}-win-x64")
set(_msi_path "${SQLITEBROWSER_MSI_ARTIFACT_DIR}/${_artifact_base}.msi")
set(_wix_pdb_path
    "${SQLITEBROWSER_MSI_ARTIFACT_DIR}/${_artifact_base}.wixpdb")

message(STATUS
    "Building MSI with WixToolset.Sdk ${SQLITEBROWSER_MSI_WIX_VERSION}")
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env VSLANG=1033
        "${SQLITEBROWSER_MSI_MSBUILD}"
        "${SQLITEBROWSER_MSI_WIX_PROJECT}"
        -nologo
        -m
        -restore
        -t:Build
        -p:Configuration=Release
        -p:Platform=x64
        "-p:PayloadRoot=${SQLITEBROWSER_MSI_RUNTIME_DIR}"
        "-p:PackageVersion=${SQLITEBROWSER_MSI_VERSION}"
        "-p:ProductName=${SQLITEBROWSER_MSI_PRODUCT_NAME}"
        "-p:Manufacturer=${SQLITEBROWSER_MSI_MANUFACTURER}"
        "-p:UpgradeCode=${SQLITEBROWSER_MSI_UPGRADE_CODE}"
        "-p:WixSdkVersion=${SQLITEBROWSER_MSI_WIX_VERSION}"
        "-p:PackageOutput=${SQLITEBROWSER_MSI_ARTIFACT_DIR}"
        "-p:WixIntermediateRoot=${SQLITEBROWSER_MSI_WORK_DIR}"
        "-p:SourceRoot=${SQLITEBROWSER_MSI_SOURCE_DIR}"
    RESULT_VARIABLE _msbuild_result
    COMMAND_ECHO STDOUT
    ECHO_OUTPUT_VARIABLE
    ECHO_ERROR_VARIABLE)
if(NOT _msbuild_result EQUAL 0)
    message(FATAL_ERROR
        "WiX MSI build failed with exit code ${_msbuild_result}.\n"
        "If the output contains WIX7015, review the WiX 7 OSMF EULA and "
        "accept it explicitly; this repository does not accept it for you.")
endif()

if(NOT EXISTS "${_msi_path}")
    message(FATAL_ERROR "WiX did not produce the expected MSI: ${_msi_path}")
endif()
if(NOT EXISTS "${_wix_pdb_path}")
    message(FATAL_ERROR
        "WiX did not produce the expected debug database: ${_wix_pdb_path}")
endif()

file(REMOVE_RECURSE "${SQLITEBROWSER_MSI_VERIFY_DIR}")
file(MAKE_DIRECTORY "${SQLITEBROWSER_MSI_VERIFY_DIR}")
set(_admin_log "${SQLITEBROWSER_MSI_WORK_DIR}/administrative-install.log")
cmake_path(NATIVE_PATH _msi_path NORMALIZE _msi_native_path)
cmake_path(NATIVE_PATH SQLITEBROWSER_MSI_VERIFY_DIR NORMALIZE
    _verify_native_path)
cmake_path(NATIVE_PATH _admin_log NORMALIZE _admin_log_native_path)
execute_process(
    COMMAND msiexec.exe /a "${_msi_native_path}" /qn
        "TARGETDIR=${_verify_native_path}" "/l*v" "${_admin_log_native_path}"
    RESULT_VARIABLE _admin_result
    COMMAND_ECHO STDOUT)
if(NOT _admin_result EQUAL 0)
    message(FATAL_ERROR
        "MSI administrative extraction failed with exit code ${_admin_result}.\n"
        "Log: ${_admin_log}")
endif()

file(GLOB_RECURSE _admin_files
    LIST_DIRECTORIES FALSE
    "${SQLITEBROWSER_MSI_VERIFY_DIR}/*")
set(_admin_apps)
foreach(_admin_file IN LISTS _admin_files)
    cmake_path(GET _admin_file FILENAME _admin_file_name)
    if("${_admin_file_name}" STREQUAL "${SQLITEBROWSER_MSI_APP_NAME}")
        list(APPEND _admin_apps "${_admin_file}")
    endif()
endforeach()
list(LENGTH _admin_apps _admin_app_count)
if(NOT _admin_app_count EQUAL 1)
    message(FATAL_ERROR
        "Expected one application executable in the administrative image; "
        "found ${_admin_app_count}.")
endif()
list(GET _admin_apps 0 _admin_app)
cmake_path(GET _admin_app PARENT_PATH _admin_runtime_dir)
_sqlitebrowser_validate_runtime(
    "${_admin_runtime_dir}" Release PACKAGE "${SQLITEBROWSER_MSI_APP_NAME}")

foreach(_relative_path IN LISTS _manifest_paths)
    file(SHA256 "${_admin_runtime_dir}/${_relative_path}" _admin_hash)
    file(SHA256 "${SQLITEBROWSER_MSI_RUNTIME_DIR}/${_relative_path}" _source_hash)
    if(NOT _admin_hash STREQUAL _source_hash)
        message(FATAL_ERROR
            "Administrative image differs from the package runtime: "
            "${_relative_path}")
    endif()
endforeach()

file(SHA256 "${_msi_path}" _msi_hash)
file(SIZE "${_msi_path}" _msi_size)
execute_process(
    COMMAND git -C "${SQLITEBROWSER_MSI_SOURCE_DIR}" rev-parse HEAD
    OUTPUT_VARIABLE _git_commit
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
if(_git_commit STREQUAL "")
    set(_git_commit "Unknown")
endif()
string(CONCAT _msi_manifest
    "SQLiteBrowser Windows MSI manifest\n"
    "Format version: 1\n"
    "Version: ${SQLITEBROWSER_MSI_VERSION}\n"
    "Architecture: x64\n"
    "Configuration: Release\n"
    "WiX SDK: ${SQLITEBROWSER_MSI_WIX_VERSION}\n"
    "Git commit: ${_git_commit}\n"
    "Payload manifest: package/metadata/runtime-manifest.txt\n"
    "MSI: ${_artifact_base}.msi\n"
    "MSI size: ${_msi_size}\n"
    "MSI SHA-256: ${_msi_hash}\n")
file(WRITE
    "${SQLITEBROWSER_MSI_CONFIGURATION_ROOT}/package/metadata/msi-manifest.txt"
    "${_msi_manifest}")

message(STATUS "SQLiteBrowser MSI verified: ${_msi_path}")
message(STATUS "WiX debug database retained: ${_wix_pdb_path}")
