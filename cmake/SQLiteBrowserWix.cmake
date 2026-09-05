include_guard(GLOBAL)

include(CMakeParseArguments)

function(sqlitebrowser_add_windows_msi)
    cmake_parse_arguments(PARSE_ARGV 0 MSI
        ""
        "TARGET;RUNTIME_TARGET;RUNTIME_DIR;MANIFEST;WIX_PROJECT;SOURCE_DIR"
        "")

    foreach(_required_argument IN ITEMS
            TARGET RUNTIME_TARGET RUNTIME_DIR MANIFEST WIX_PROJECT SOURCE_DIR)
        if(MSI_${_required_argument} STREQUAL "")
            message(FATAL_ERROR
                "SQLiteBrowser MSI packaging requires ${_required_argument}.")
        endif()
    endforeach()

    if(NOT TARGET "${MSI_TARGET}")
        message(FATAL_ERROR "MSI application target does not exist: ${MSI_TARGET}")
    endif()
    if(NOT TARGET "${MSI_RUNTIME_TARGET}")
        message(FATAL_ERROR
            "MSI runtime verification target does not exist: ${MSI_RUNTIME_TARGET}")
    endif()
    if(NOT EXISTS "${MSI_WIX_PROJECT}")
        message(FATAL_ERROR "WiX project does not exist: ${MSI_WIX_PROJECT}")
    endif()
    if(CMAKE_VS_MSBUILD_COMMAND STREQUAL ""
            OR NOT EXISTS "${CMAKE_VS_MSBUILD_COMMAND}")
        message(FATAL_ERROR
            "Visual Studio 2022 MSBuild was not provided by the CMake generator.")
    endif()

    _sqlitebrowser_runtime_configuration(_msi_configuration)
    if(NOT _msi_configuration STREQUAL "Release")
        message(STATUS
            "SQLiteBrowser MSI target is disabled for ${_msi_configuration}; "
            "MSI packaging is Release-only.")
        return()
    endif()

    set(SQLITEBROWSER_MSI_WIX_VERSION "7.0.0" CACHE STRING
        "Exact WixToolset SDK and extension version used by the MSI project")
    set(SQLITEBROWSER_MSI_MANUFACTURER "DB Browser for SQLite Team" CACHE STRING
        "Windows Installer Manufacturer value")
    set(SQLITEBROWSER_MSI_UPGRADE_CODE
        "124623D9-35D6-4D2E-9474-2ADACC8BABBB" CACHE STRING
        "Stable Windows Installer UpgradeCode")
    mark_as_advanced(
        SQLITEBROWSER_MSI_WIX_VERSION
        SQLITEBROWSER_MSI_MANUFACTURER
        SQLITEBROWSER_MSI_UPGRADE_CODE)

    set(_msi_build_script
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/BuildSQLiteBrowserMsi.cmake")
    set(_msi_artifact_dir
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/package/artifacts")
    set(_msi_work_dir
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/package/build/wix")
    set(_msi_verify_dir
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/package/verify/msi-admin-image")

    add_custom_target(sqlitebrowser_msi
        COMMAND "${CMAKE_COMMAND}"
            "-DSQLITEBROWSER_MSI_SOURCE_DIR=${MSI_SOURCE_DIR}"
            "-DSQLITEBROWSER_MSI_CONFIGURATION_ROOT=${SQLITEBROWSER_CONFIGURATION_ROOT}"
            "-DSQLITEBROWSER_MSI_RUNTIME_DIR=${MSI_RUNTIME_DIR}"
            "-DSQLITEBROWSER_MSI_RUNTIME_MANIFEST=${MSI_MANIFEST}"
            "-DSQLITEBROWSER_MSI_WIX_PROJECT=${MSI_WIX_PROJECT}"
            "-DSQLITEBROWSER_MSI_MSBUILD=${CMAKE_VS_MSBUILD_COMMAND}"
            "-DSQLITEBROWSER_MSI_WIX_VERSION=${SQLITEBROWSER_MSI_WIX_VERSION}"
            "-DSQLITEBROWSER_MSI_VERSION=${PROJECT_VERSION}"
            "-DSQLITEBROWSER_MSI_PRODUCT_NAME=DB Browser for SQLCipher"
            "-DSQLITEBROWSER_MSI_MANUFACTURER=${SQLITEBROWSER_MSI_MANUFACTURER}"
            "-DSQLITEBROWSER_MSI_UPGRADE_CODE=${SQLITEBROWSER_MSI_UPGRADE_CODE}"
            "-DSQLITEBROWSER_MSI_APP_NAME=$<TARGET_FILE_NAME:${MSI_TARGET}>"
            "-DSQLITEBROWSER_MSI_ARTIFACT_DIR=${_msi_artifact_dir}"
            "-DSQLITEBROWSER_MSI_WORK_DIR=${_msi_work_dir}"
            "-DSQLITEBROWSER_MSI_VERIFY_DIR=${_msi_verify_dir}"
            -P "${_msi_build_script}"
        DEPENDS "${MSI_RUNTIME_TARGET}"
        COMMENT
            "Building and verifying the SQLiteBrowser ${PROJECT_VERSION} x64 MSI with WiX"
        VERBATIM)
    set_target_properties(sqlitebrowser_msi PROPERTIES FOLDER "Packaging")

    message(STATUS
        "SQLiteBrowser WiX MSI: Release x64 -> ${_msi_artifact_dir}")
endfunction()
