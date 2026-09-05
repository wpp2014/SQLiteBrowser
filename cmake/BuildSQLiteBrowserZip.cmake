cmake_minimum_required(VERSION 3.30.3)

foreach(_required_variable IN ITEMS
        SQLITEBROWSER_ZIP_SOURCE_DIR
        SQLITEBROWSER_ZIP_CONFIGURATION_ROOT
        SQLITEBROWSER_ZIP_RUNTIME_DIR
        SQLITEBROWSER_ZIP_RUNTIME_MANIFEST
        SQLITEBROWSER_ZIP_VERSION
        SQLITEBROWSER_ZIP_APP_NAME
        SQLITEBROWSER_ZIP_SMOKE_EXECUTABLE
        SQLITEBROWSER_ZIP_TLS_URL
        SQLITEBROWSER_ZIP_ARTIFACT_DIR
        SQLITEBROWSER_ZIP_WORK_DIR
        SQLITEBROWSER_ZIP_VERIFY_DIR)
    if(NOT DEFINED ${_required_variable}
            OR "${${_required_variable}}" STREQUAL "")
        message(FATAL_ERROR "Missing required ZIP variable: ${_required_variable}")
    endif()
endforeach()

if(NOT SQLITEBROWSER_ZIP_VERSION MATCHES "^[0-9]+\.[0-9]+\.[0-9]+$")
    message(FATAL_ERROR
        "ZIP version must contain exactly three numeric fields: "
        "${SQLITEBROWSER_ZIP_VERSION}")
endif()

foreach(_path_variable IN ITEMS
        SQLITEBROWSER_ZIP_SOURCE_DIR
        SQLITEBROWSER_ZIP_CONFIGURATION_ROOT
        SQLITEBROWSER_ZIP_RUNTIME_DIR
        SQLITEBROWSER_ZIP_RUNTIME_MANIFEST
        SQLITEBROWSER_ZIP_SMOKE_EXECUTABLE
        SQLITEBROWSER_ZIP_ARTIFACT_DIR
        SQLITEBROWSER_ZIP_WORK_DIR
        SQLITEBROWSER_ZIP_VERIFY_DIR)
    cmake_path(ABSOLUTE_PATH ${_path_variable} NORMALIZE
        OUTPUT_VARIABLE _normalized_path)
    set(${_path_variable} "${_normalized_path}")
endforeach()

set(_expected_runtime_dir
    "${SQLITEBROWSER_ZIP_CONFIGURATION_ROOT}/package/runtime")
set(_expected_manifest
    "${SQLITEBROWSER_ZIP_CONFIGURATION_ROOT}/package/metadata/runtime-manifest.txt")
set(_expected_artifact_dir
    "${SQLITEBROWSER_ZIP_CONFIGURATION_ROOT}/package/artifacts")
set(_expected_work_dir
    "${SQLITEBROWSER_ZIP_CONFIGURATION_ROOT}/package/build/zip")
set(_expected_verify_dir
    "${SQLITEBROWSER_ZIP_CONFIGURATION_ROOT}/package/verify/zip")
foreach(_expected_path_variable IN ITEMS
        _expected_runtime_dir _expected_manifest _expected_artifact_dir
        _expected_work_dir _expected_verify_dir)
    cmake_path(NORMAL_PATH ${_expected_path_variable})
endforeach()

foreach(_path_pair IN ITEMS
        "SQLITEBROWSER_ZIP_RUNTIME_DIR;_expected_runtime_dir"
        "SQLITEBROWSER_ZIP_RUNTIME_MANIFEST;_expected_manifest"
        "SQLITEBROWSER_ZIP_ARTIFACT_DIR;_expected_artifact_dir"
        "SQLITEBROWSER_ZIP_WORK_DIR;_expected_work_dir"
        "SQLITEBROWSER_ZIP_VERIFY_DIR;_expected_verify_dir")
    list(GET _path_pair 0 _actual_variable)
    list(GET _path_pair 1 _expected_variable)
    cmake_path(COMPARE
        "${${_actual_variable}}" EQUAL "${${_expected_variable}}" _matches)
    if(NOT _matches)
        message(FATAL_ERROR
            "Unsafe ZIP path for ${_actual_variable}.\n"
            "Expected: ${${_expected_variable}}\n"
            "Actual:   ${${_actual_variable}}")
    endif()
endforeach()

cmake_path(GET SQLITEBROWSER_ZIP_CONFIGURATION_ROOT FILENAME _root_name)
cmake_path(GET SQLITEBROWSER_ZIP_CONFIGURATION_ROOT PARENT_PATH _output_dir)
cmake_path(GET _output_dir FILENAME _output_name)
if(NOT _root_name STREQUAL "x64-shared-release"
        OR NOT _output_name STREQUAL "output")
    message(FATAL_ERROR
        "ZIP packaging is restricted to output/x64-shared-release; actual: "
        "${SQLITEBROWSER_ZIP_CONFIGURATION_ROOT}")
endif()

if(NOT IS_DIRECTORY "${SQLITEBROWSER_ZIP_RUNTIME_DIR}")
    message(FATAL_ERROR
        "Release package runtime is missing: ${SQLITEBROWSER_ZIP_RUNTIME_DIR}")
endif()
if(NOT EXISTS "${SQLITEBROWSER_ZIP_RUNTIME_MANIFEST}")
    message(FATAL_ERROR
        "Release runtime manifest is missing: ${SQLITEBROWSER_ZIP_RUNTIME_MANIFEST}")
endif()
if(NOT EXISTS "${SQLITEBROWSER_ZIP_SMOKE_EXECUTABLE}")
    message(FATAL_ERROR
        "Runtime smoke executable is missing: ${SQLITEBROWSER_ZIP_SMOKE_EXECUTABLE}")
endif()

include("${SQLITEBROWSER_ZIP_SOURCE_DIR}/cmake/SQLiteBrowserWindowsRuntime.cmake")

function(_sqlitebrowser_zip_validate_manifest runtime_dir manifest output_paths)
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
    "${SQLITEBROWSER_ZIP_RUNTIME_DIR}" Release PACKAGE
    "${SQLITEBROWSER_ZIP_APP_NAME}")
_sqlitebrowser_zip_validate_manifest(
    "${SQLITEBROWSER_ZIP_RUNTIME_DIR}"
    "${SQLITEBROWSER_ZIP_RUNTIME_MANIFEST}"
    _manifest_paths)

if(EXISTS "${SQLITEBROWSER_ZIP_RUNTIME_DIR}/vc_redist.x64.exe")
    message(WARNING
        "The current runtime still contains vc_redist.x64.exe. The ZIP will "
        "carry it as an ordinary file and will not execute it. Replace this "
        "with an app-local VC143 runtime before a production release.")
endif()

set(_artifact_base
    "DB.Browser.for.SQLCipher-${SQLITEBROWSER_ZIP_VERSION}-win-x64")
set(_archive_root_name "DB Browser for SQLCipher")
set(_zip_path "${SQLITEBROWSER_ZIP_ARTIFACT_DIR}/${_artifact_base}.zip")
set(_zip_checksum_path "${_zip_path}.sha256")
set(_archive_input "${SQLITEBROWSER_ZIP_WORK_DIR}/archive-input")
set(_archive_root "${_archive_input}/${_archive_root_name}")
set(_temporary_zip "${SQLITEBROWSER_ZIP_WORK_DIR}/${_artifact_base}.zip.next")

file(REMOVE_RECURSE
    "${SQLITEBROWSER_ZIP_WORK_DIR}"
    "${SQLITEBROWSER_ZIP_VERIFY_DIR}")
file(MAKE_DIRECTORY
    "${_archive_root}"
    "${SQLITEBROWSER_ZIP_ARTIFACT_DIR}"
    "${SQLITEBROWSER_ZIP_VERIFY_DIR}")

foreach(_relative_path IN LISTS _manifest_paths)
    set(_source_path "${SQLITEBROWSER_ZIP_RUNTIME_DIR}/${_relative_path}")
    set(_destination_path "${_archive_root}/${_relative_path}")
    cmake_path(GET _destination_path PARENT_PATH _destination_parent)
    file(MAKE_DIRECTORY "${_destination_parent}")
    file(COPY_FILE "${_source_path}" "${_destination_path}" ONLY_IF_DIFFERENT)
endforeach()
_sqlitebrowser_validate_runtime(
    "${_archive_root}" Release PACKAGE "${SQLITEBROWSER_ZIP_APP_NAME}")
_sqlitebrowser_zip_validate_manifest(
    "${_archive_root}" "${SQLITEBROWSER_ZIP_RUNTIME_MANIFEST}"
    _staged_manifest_paths)

execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar cf "${_temporary_zip}"
        --format=zip -- "${_archive_root_name}"
    WORKING_DIRECTORY "${_archive_input}"
    RESULT_VARIABLE _archive_result
    COMMAND_ECHO STDOUT)
if(NOT _archive_result EQUAL 0 OR NOT EXISTS "${_temporary_zip}")
    message(FATAL_ERROR
        "ZIP archive creation failed with exit code ${_archive_result}.")
endif()

file(REMOVE "${_zip_path}" "${_zip_checksum_path}")
file(RENAME "${_temporary_zip}" "${_zip_path}" RESULT _publish_result)
if(NOT _publish_result STREQUAL "0")
    message(FATAL_ERROR "Failed to publish ZIP archive: ${_publish_result}")
endif()

file(ARCHIVE_EXTRACT
    INPUT "${_zip_path}"
    DESTINATION "${SQLITEBROWSER_ZIP_VERIFY_DIR}")
file(GLOB _verify_entries
    LIST_DIRECTORIES TRUE
    RELATIVE "${SQLITEBROWSER_ZIP_VERIFY_DIR}"
    "${SQLITEBROWSER_ZIP_VERIFY_DIR}/*")
if(NOT _verify_entries STREQUAL _archive_root_name)
    message(FATAL_ERROR
        "ZIP must contain exactly one top-level directory named "
        "'${_archive_root_name}'; actual entries: ${_verify_entries}")
endif()

set(_extracted_runtime
    "${SQLITEBROWSER_ZIP_VERIFY_DIR}/${_archive_root_name}")
_sqlitebrowser_validate_runtime(
    "${_extracted_runtime}" Release PACKAGE "${SQLITEBROWSER_ZIP_APP_NAME}")
_sqlitebrowser_zip_validate_manifest(
    "${_extracted_runtime}" "${SQLITEBROWSER_ZIP_RUNTIME_MANIFEST}"
    _extracted_manifest_paths)

execute_process(
    COMMAND "${CMAKE_COMMAND}"
        "-DAPP_EXECUTABLE=${_extracted_runtime}/${SQLITEBROWSER_ZIP_APP_NAME}"
        "-DSMOKE_EXECUTABLE=${SQLITEBROWSER_ZIP_SMOKE_EXECUTABLE}"
        "-DRUNTIME_DIR=${_extracted_runtime}"
        "-DSMOKE_WORK_DIR=${SQLITEBROWSER_ZIP_WORK_DIR}/smoke"
        "-DTLS_URL=${SQLITEBROWSER_ZIP_TLS_URL}"
        -P "${SQLITEBROWSER_ZIP_SOURCE_DIR}/cmake/RunSQLiteBrowserWindowsSmoke.cmake"
    RESULT_VARIABLE _smoke_result
    COMMAND_ECHO STDOUT)
if(NOT _smoke_result EQUAL 0)
    message(FATAL_ERROR
        "Extracted ZIP runtime smoke failed with exit code ${_smoke_result}.")
endif()

file(SHA256 "${_zip_path}" _zip_hash)
string(TOLOWER "${_zip_hash}" _zip_hash)
file(SIZE "${_zip_path}" _zip_size)
file(WRITE "${_zip_checksum_path}"
    "${_zip_hash}  ${_artifact_base}.zip\n")

execute_process(
    COMMAND git -C "${SQLITEBROWSER_ZIP_SOURCE_DIR}" rev-parse HEAD
    OUTPUT_VARIABLE _git_commit
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
if(_git_commit STREQUAL "")
    set(_git_commit "Unknown")
endif()
string(CONCAT _zip_manifest
    "SQLiteBrowser Windows ZIP manifest\n"
    "Format version: 1\n"
    "Version: ${SQLITEBROWSER_ZIP_VERSION}\n"
    "Architecture: x64\n"
    "Configuration: Release\n"
    "Git commit: ${_git_commit}\n"
    "Payload manifest: package/metadata/runtime-manifest.txt\n"
    "Archive root: ${_archive_root_name}\n"
    "ZIP: ${_artifact_base}.zip\n"
    "ZIP size: ${_zip_size}\n"
    "ZIP SHA-256: ${_zip_hash}\n")
file(WRITE
    "${SQLITEBROWSER_ZIP_CONFIGURATION_ROOT}/package/metadata/zip-manifest.txt"
    "${_zip_manifest}")

message(STATUS "SQLiteBrowser ZIP verified: ${_zip_path}")
message(STATUS "SQLiteBrowser ZIP SHA-256: ${_zip_hash}")
