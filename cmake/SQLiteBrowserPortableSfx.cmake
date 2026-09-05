include_guard(GLOBAL)

include(CMakeParseArguments)

function(sqlitebrowser_add_windows_portable_sfx)
    cmake_parse_arguments(PARSE_ARGV 0 SFX
        ""
        "TARGET;RUNTIME_TARGET;RUNTIME_DIR;MANIFEST;SMOKE_TARGET;TLS_URL;NSIS_SCRIPT;SOURCE_DIR"
        "")

    foreach(_required_argument IN ITEMS
            TARGET RUNTIME_TARGET RUNTIME_DIR MANIFEST SMOKE_TARGET TLS_URL
            NSIS_SCRIPT SOURCE_DIR)
        if(SFX_${_required_argument} STREQUAL "")
            message(FATAL_ERROR
                "SQLiteBrowser portable SFX requires ${_required_argument}.")
        endif()
    endforeach()

    foreach(_required_target IN ITEMS
            "${SFX_TARGET}" "${SFX_RUNTIME_TARGET}" "${SFX_SMOKE_TARGET}")
        if(NOT TARGET "${_required_target}")
            message(FATAL_ERROR
                "Portable SFX target does not exist: ${_required_target}")
        endif()
    endforeach()

    if(NOT EXISTS "${SFX_NSIS_SCRIPT}")
        message(FATAL_ERROR
            "Portable SFX NSIS script does not exist: ${SFX_NSIS_SCRIPT}")
    endif()

    _sqlitebrowser_runtime_configuration(_sfx_configuration)
    if(NOT _sfx_configuration STREQUAL "Release")
        message(STATUS
            "SQLiteBrowser portable SFX target is disabled for "
            "${_sfx_configuration}; release artifacts are Release-only.")
        return()
    endif()

    set(_sfx_build_script
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/BuildSQLiteBrowserPortableSfx.cmake")
    set(_sfx_artifact_dir
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/package/artifacts")
    set(_sfx_work_dir
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/package/build/nsis-portable")
    set(_sfx_verify_dir
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/package/verify/portable-sfx")

    add_custom_target(sqlitebrowser_portable_sfx
        COMMAND "${CMAKE_COMMAND}"
            "-DSQLITEBROWSER_SFX_SOURCE_DIR=${SFX_SOURCE_DIR}"
            "-DSQLITEBROWSER_SFX_CONFIGURATION_ROOT=${SQLITEBROWSER_CONFIGURATION_ROOT}"
            "-DSQLITEBROWSER_SFX_RUNTIME_DIR=${SFX_RUNTIME_DIR}"
            "-DSQLITEBROWSER_SFX_RUNTIME_MANIFEST=${SFX_MANIFEST}"
            "-DSQLITEBROWSER_SFX_VERSION=${PROJECT_VERSION}"
            "-DSQLITEBROWSER_SFX_APP_NAME=$<TARGET_FILE_NAME:${SFX_TARGET}>"
            "-DSQLITEBROWSER_SFX_SMOKE_EXECUTABLE=$<TARGET_FILE:${SFX_SMOKE_TARGET}>"
            "-DSQLITEBROWSER_SFX_TLS_URL=${SFX_TLS_URL}"
            "-DSQLITEBROWSER_SFX_NSIS_SCRIPT=${SFX_NSIS_SCRIPT}"
            "-DSQLITEBROWSER_SFX_ARTIFACT_DIR=${_sfx_artifact_dir}"
            "-DSQLITEBROWSER_SFX_WORK_DIR=${_sfx_work_dir}"
            "-DSQLITEBROWSER_SFX_VERIFY_DIR=${_sfx_verify_dir}"
            -P "${_sfx_build_script}"
        DEPENDS "${SFX_RUNTIME_TARGET}" "${SFX_SMOKE_TARGET}"
        COMMENT
            "Building and verifying the SQLiteBrowser ${PROJECT_VERSION} portable SFX"
        VERBATIM)
    set_target_properties(sqlitebrowser_portable_sfx PROPERTIES
        FOLDER "Packaging")

    message(STATUS
        "SQLiteBrowser portable SFX: Release x64 -> ${_sfx_artifact_dir}")
endfunction()
