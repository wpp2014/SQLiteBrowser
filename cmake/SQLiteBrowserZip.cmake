include_guard(GLOBAL)

include(CMakeParseArguments)

function(sqlitebrowser_add_windows_zip)
    cmake_parse_arguments(PARSE_ARGV 0 ZIP
        ""
        "TARGET;RUNTIME_TARGET;RUNTIME_DIR;MANIFEST;SMOKE_TARGET;TLS_URL;SOURCE_DIR"
        "")

    foreach(_required_argument IN ITEMS
            TARGET RUNTIME_TARGET RUNTIME_DIR MANIFEST SMOKE_TARGET TLS_URL
            SOURCE_DIR)
        if(ZIP_${_required_argument} STREQUAL "")
            message(FATAL_ERROR
                "SQLiteBrowser ZIP packaging requires ${_required_argument}.")
        endif()
    endforeach()

    foreach(_required_target IN ITEMS
            "${ZIP_TARGET}" "${ZIP_RUNTIME_TARGET}" "${ZIP_SMOKE_TARGET}")
        if(NOT TARGET "${_required_target}")
            message(FATAL_ERROR
                "ZIP packaging target does not exist: ${_required_target}")
        endif()
    endforeach()

    _sqlitebrowser_runtime_configuration(_zip_configuration)
    if(NOT _zip_configuration STREQUAL "Release")
        message(STATUS
            "SQLiteBrowser ZIP target is disabled for ${_zip_configuration}; "
            "release archives are Release-only.")
        return()
    endif()

    set(_zip_build_script
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/BuildSQLiteBrowserZip.cmake")
    set(_zip_artifact_dir
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/package/artifacts")
    set(_zip_work_dir
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/package/build/zip")
    set(_zip_verify_dir
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/package/verify/zip")

    add_custom_target(sqlitebrowser_zip
        COMMAND "${CMAKE_COMMAND}"
            "-DSQLITEBROWSER_ZIP_SOURCE_DIR=${ZIP_SOURCE_DIR}"
            "-DSQLITEBROWSER_ZIP_CONFIGURATION_ROOT=${SQLITEBROWSER_CONFIGURATION_ROOT}"
            "-DSQLITEBROWSER_ZIP_RUNTIME_DIR=${ZIP_RUNTIME_DIR}"
            "-DSQLITEBROWSER_ZIP_RUNTIME_MANIFEST=${ZIP_MANIFEST}"
            "-DSQLITEBROWSER_ZIP_VERSION=${PROJECT_VERSION}"
            "-DSQLITEBROWSER_ZIP_APP_NAME=$<TARGET_FILE_NAME:${ZIP_TARGET}>"
            "-DSQLITEBROWSER_ZIP_SMOKE_EXECUTABLE=$<TARGET_FILE:${ZIP_SMOKE_TARGET}>"
            "-DSQLITEBROWSER_ZIP_TLS_URL=${ZIP_TLS_URL}"
            "-DSQLITEBROWSER_ZIP_ARTIFACT_DIR=${_zip_artifact_dir}"
            "-DSQLITEBROWSER_ZIP_WORK_DIR=${_zip_work_dir}"
            "-DSQLITEBROWSER_ZIP_VERIFY_DIR=${_zip_verify_dir}"
            -P "${_zip_build_script}"
        DEPENDS "${ZIP_RUNTIME_TARGET}" "${ZIP_SMOKE_TARGET}"
        COMMENT
            "Building and verifying the SQLiteBrowser ${PROJECT_VERSION} x64 ZIP"
        VERBATIM)
    set_target_properties(sqlitebrowser_zip PROPERTIES FOLDER "Packaging")

    message(STATUS
        "SQLiteBrowser ZIP: Release x64 -> ${_zip_artifact_dir}")
endfunction()
