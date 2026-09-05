include_guard(GLOBAL)

include(CMakeParseArguments)

function(_sqlitebrowser_runtime_file_list configuration kind app_name output_variable)
    if(NOT configuration MATCHES "^(Debug|Release)$")
        message(FATAL_ERROR "Runtime configuration must be Debug or Release.")
    endif()
    if(NOT kind MATCHES "^(DEVELOPMENT|PACKAGE)$")
        message(FATAL_ERROR "Runtime kind must be DEVELOPMENT or PACKAGE.")
    endif()
    if(app_name STREQUAL "")
        message(FATAL_ERROR "Runtime application file name must not be empty.")
    endif()

    if(configuration STREQUAL "Debug")
        set(_qt_suffix "d")
    else()
        set(_qt_suffix "")
    endif()

    set(_runtime_files
        "${app_name}"
        "sqlcipher.dll"
        "libcrypto-3-x64.dll"
        "libssl-3-x64.dll"
        "brotlicommon.dll"
        "brotlidec.dll"
        "brotlienc.dll"
        "Qt6Core${_qt_suffix}.dll"
        "Qt6Core5Compat${_qt_suffix}.dll"
        "Qt6Gui${_qt_suffix}.dll"
        "Qt6Network${_qt_suffix}.dll"
        "Qt6Pdf${_qt_suffix}.dll"
        "Qt6PrintSupport${_qt_suffix}.dll"
        "Qt6Svg${_qt_suffix}.dll"
        "Qt6Widgets${_qt_suffix}.dll"
        "Qt6Xml${_qt_suffix}.dll"
        "D3Dcompiler_47.dll"
        "dxcompiler.dll"
        "dxil.dll"
        "opengl32sw.dll"
        "generic/qtuiotouchplugin${_qt_suffix}.dll"
        "iconengines/qsvgicon${_qt_suffix}.dll"
        "imageformats/qgif${_qt_suffix}.dll"
        "imageformats/qicns${_qt_suffix}.dll"
        "imageformats/qico${_qt_suffix}.dll"
        "imageformats/qjpeg${_qt_suffix}.dll"
        "imageformats/qpdf${_qt_suffix}.dll"
        "imageformats/qsvg${_qt_suffix}.dll"
        "imageformats/qtga${_qt_suffix}.dll"
        "imageformats/qtiff${_qt_suffix}.dll"
        "imageformats/qwbmp${_qt_suffix}.dll"
        "imageformats/qwebp${_qt_suffix}.dll"
        "networkinformation/qnetworklistmanager${_qt_suffix}.dll"
        "platforms/qwindows${_qt_suffix}.dll"
        "styles/qmodernwindowsstyle${_qt_suffix}.dll"
        "tls/qcertonlybackend${_qt_suffix}.dll"
        "tls/qopensslbackend${_qt_suffix}.dll"
        "tls/qschannelbackend${_qt_suffix}.dll"
    )

    foreach(_translation IN ITEMS
            ar bg ca cs da de en es fa fi fr gd he hr hu it ja ka ko lg lv nl nn
            pl pt_BR ru sk sv tr uk zh_CN zh_TW)
        list(APPEND _runtime_files "translations/qt_${_translation}.qm")
    endforeach()

    # windeployqt places the redistributable installer in the Release
    # development directory. Keep validating that source output, but never
    # publish the installer as part of the application runtime.
    if(configuration STREQUAL "Release" AND kind STREQUAL "DEVELOPMENT")
        list(APPEND _runtime_files "vc_redist.x64.exe")
    endif()

    if(kind STREQUAL "DEVELOPMENT")
        string(REGEX REPLACE "\\.[Ee][Xx][Ee]$" ".pdb" _app_pdb "${app_name}")
        list(APPEND _runtime_files
            "${_app_pdb}"
            "brotlicommon.lib" "brotlicommon.pdb"
            "brotlidec.lib" "brotlidec.pdb"
            "brotlienc.lib" "brotlienc.pdb"
            "libcrypto-3-x64.pdb" "libcrypto.lib"
            "libssl-3-x64.pdb" "libssl.lib"
            "sqlcipher.lib" "sqlcipher.pdb"
            "zlib1.dll" "zlib1.lib" "zlib1.pdb"
            "libzstd.dll" "libzstd.lib" "libzstd.pdb")
    endif()

    list(REMOVE_DUPLICATES _runtime_files)
    list(SORT _runtime_files)
    set(${output_variable} "${_runtime_files}" PARENT_SCOPE)
endfunction()

function(_sqlitebrowser_validate_runtime runtime_dir configuration kind app_name)
    file(TO_CMAKE_PATH "${runtime_dir}" _runtime_dir)
    if(NOT IS_DIRECTORY "${_runtime_dir}")
        message(FATAL_ERROR "Runtime directory does not exist: ${_runtime_dir}")
    endif()

    _sqlitebrowser_runtime_file_list(
        "${configuration}" "${kind}" "${app_name}" _allowed_runtime_files)
    set(_runtime_errors)
    foreach(_relative_path IN LISTS _allowed_runtime_files)
        set(_absolute_path "${_runtime_dir}/${_relative_path}")
        if(NOT EXISTS "${_absolute_path}")
            list(APPEND _runtime_errors "missing: ${_relative_path}")
        else()
            file(SIZE "${_absolute_path}" _file_size)
            if(_file_size EQUAL 0)
                list(APPEND _runtime_errors "empty: ${_relative_path}")
            endif()
        endif()
    endforeach()

    file(GLOB_RECURSE _actual_runtime_files
        LIST_DIRECTORIES FALSE
        RELATIVE "${_runtime_dir}"
        "${_runtime_dir}/*")
    foreach(_relative_path IN LISTS _actual_runtime_files)
        string(REPLACE "\\" "/" _relative_path "${_relative_path}")
        list(FIND _allowed_runtime_files "${_relative_path}" _allowed_index)
        if(_allowed_index EQUAL -1)
            list(APPEND _runtime_errors "unexpected: ${_relative_path}")
        endif()
    endforeach()

    if(_runtime_errors)
        list(JOIN _runtime_errors "\n  " _runtime_error_text)
        message(FATAL_ERROR
            "SQLiteBrowser ${kind} runtime validation failed in ${_runtime_dir}:\n"
            "  ${_runtime_error_text}")
    endif()

    list(LENGTH _allowed_runtime_files _runtime_file_count)
    message(STATUS
        "SQLiteBrowser ${configuration} ${kind} runtime validated: "
        "${_runtime_dir} (${_runtime_file_count} files)")
endfunction()

function(_sqlitebrowser_assert_package_paths
        configuration_root source_dir package_dir manifest_path configuration)
    cmake_path(ABSOLUTE_PATH configuration_root NORMALIZE
        OUTPUT_VARIABLE _configuration_root)
    cmake_path(ABSOLUTE_PATH package_dir NORMALIZE
        OUTPUT_VARIABLE _package_dir)
    cmake_path(ABSOLUTE_PATH source_dir NORMALIZE
        OUTPUT_VARIABLE _source_dir)
    cmake_path(ABSOLUTE_PATH manifest_path NORMALIZE
        OUTPUT_VARIABLE _manifest_path)

    set(_expected_package_dir "${_configuration_root}/package/runtime")
    set(_expected_source_dir "${_configuration_root}/bin")
    set(_expected_manifest_path
        "${_configuration_root}/package/metadata/runtime-manifest.txt")
    cmake_path(NORMAL_PATH _expected_package_dir)
    cmake_path(NORMAL_PATH _expected_source_dir)
    cmake_path(NORMAL_PATH _expected_manifest_path)

    cmake_path(COMPARE "${_package_dir}" EQUAL "${_expected_package_dir}"
        _package_dir_matches)
    cmake_path(COMPARE "${_source_dir}" EQUAL "${_expected_source_dir}"
        _source_dir_matches)
    cmake_path(COMPARE "${_manifest_path}" EQUAL "${_expected_manifest_path}"
        _manifest_path_matches)
    string(TOLOWER "${configuration}" _configuration_lower)
    set(_expected_root_name "x64-shared-${_configuration_lower}")
    cmake_path(GET _configuration_root FILENAME _configuration_root_name)
    cmake_path(GET _configuration_root PARENT_PATH _output_root)
    cmake_path(GET _output_root FILENAME _output_root_name)

    if(NOT _package_dir_matches
        OR NOT _source_dir_matches
        OR NOT _manifest_path_matches
        OR NOT _configuration_root_name STREQUAL _expected_root_name
        OR NOT _output_root_name STREQUAL "output")
        message(FATAL_ERROR
            "Package runtime paths must remain inside the configuration root.\n"
            "Expected configuration root suffix: output/${_expected_root_name}\n"
            "Actual configuration root: ${_configuration_root}\n"
            "Expected source: ${_expected_source_dir}\n"
            "Actual source:   ${_source_dir}\n"
            "Expected runtime: ${_expected_package_dir}\n"
            "Actual runtime:   ${_package_dir}\n"
            "Expected manifest: ${_expected_manifest_path}\n"
            "Actual manifest:   ${_manifest_path}")
    endif()
endfunction()

function(_sqlitebrowser_assemble_package_runtime)
    foreach(_required_variable IN ITEMS
            SQLITEBROWSER_PACKAGE_CONFIGURATION_ROOT
            SQLITEBROWSER_PACKAGE_SOURCE_DIR
            SQLITEBROWSER_PACKAGE_RUNTIME_DIR
            SQLITEBROWSER_PACKAGE_MANIFEST
            SQLITEBROWSER_PACKAGE_CONFIGURATION
            SQLITEBROWSER_PACKAGE_APP_NAME)
        if(NOT DEFINED ${_required_variable}
            OR "${${_required_variable}}" STREQUAL "")
            message(FATAL_ERROR
                "Missing required package variable: ${_required_variable}")
        endif()
    endforeach()

    set(_configuration "${SQLITEBROWSER_PACKAGE_CONFIGURATION}")
    set(_app_name "${SQLITEBROWSER_PACKAGE_APP_NAME}")
    cmake_path(ABSOLUTE_PATH SQLITEBROWSER_PACKAGE_CONFIGURATION_ROOT NORMALIZE
        OUTPUT_VARIABLE _configuration_root)
    cmake_path(ABSOLUTE_PATH SQLITEBROWSER_PACKAGE_SOURCE_DIR NORMALIZE
        OUTPUT_VARIABLE _source_dir)
    cmake_path(ABSOLUTE_PATH SQLITEBROWSER_PACKAGE_RUNTIME_DIR NORMALIZE
        OUTPUT_VARIABLE _package_dir)
    cmake_path(ABSOLUTE_PATH SQLITEBROWSER_PACKAGE_MANIFEST NORMALIZE
        OUTPUT_VARIABLE _manifest_path)

    _sqlitebrowser_assert_package_paths(
        "${_configuration_root}" "${_source_dir}" "${_package_dir}"
        "${_manifest_path}" "${_configuration}")
    _sqlitebrowser_validate_runtime(
        "${_source_dir}" "${_configuration}" DEVELOPMENT "${_app_name}")
    _sqlitebrowser_runtime_file_list(
        "${_configuration}" PACKAGE "${_app_name}" _package_files)
    list(FIND _package_files "vc_redist.x64.exe" _vc_redist_index)
    if(NOT _vc_redist_index EQUAL -1)
        message(FATAL_ERROR
            "vc_redist.x64.exe must not be included in a published runtime.")
    endif()

    set(_work_root "${_configuration_root}/build/package-runtime")
    set(_next_dir "${_work_root}/next")
    file(REMOVE_RECURSE "${_next_dir}")
    file(MAKE_DIRECTORY "${_next_dir}")

    foreach(_relative_path IN LISTS _package_files)
        set(_source_path "${_source_dir}/${_relative_path}")
        set(_destination_path "${_next_dir}/${_relative_path}")
        cmake_path(GET _destination_path PARENT_PATH _destination_parent)
        file(MAKE_DIRECTORY "${_destination_parent}")
        file(COPY_FILE "${_source_path}" "${_destination_path}" ONLY_IF_DIFFERENT)
    endforeach()

    _sqlitebrowser_validate_runtime(
        "${_next_dir}" "${_configuration}" PACKAGE "${_app_name}")

    file(REMOVE_RECURSE "${_package_dir}")
    cmake_path(GET _package_dir PARENT_PATH _package_parent)
    file(MAKE_DIRECTORY "${_package_parent}")
    file(RENAME "${_next_dir}" "${_package_dir}" RESULT _rename_result)
    if(NOT _rename_result STREQUAL "0")
        message(FATAL_ERROR
            "Failed to publish package runtime: ${_rename_result}")
    endif()

    cmake_path(GET _manifest_path PARENT_PATH _manifest_parent)
    file(MAKE_DIRECTORY "${_manifest_parent}")
    set(_manifest_lines
        "SQLiteBrowser Windows package runtime manifest"
        "Format version: 1"
        "Configuration: ${_configuration}"
        "Architecture: x64"
        "Source kind: validated development output"
        "Runtime policy: strict allowlist"
        "Publication exclusions: vc_redist.x64.exe"
        "Files:")
    foreach(_relative_path IN LISTS _package_files)
        file(SHA256 "${_package_dir}/${_relative_path}" _file_hash)
        list(APPEND _manifest_lines "${_file_hash}\t${_relative_path}")
    endforeach()
    list(JOIN _manifest_lines "\n" _manifest_text)
    file(WRITE "${_manifest_path}" "${_manifest_text}\n")

    _sqlitebrowser_validate_runtime(
        "${_package_dir}" "${_configuration}" PACKAGE "${_app_name}")
    message(STATUS "SQLiteBrowser package manifest: ${_manifest_path}")
endfunction()

if(DEFINED SQLITEBROWSER_RUNTIME_VERIFY_DIR)
    foreach(_required_variable IN ITEMS
            SQLITEBROWSER_RUNTIME_VERIFY_CONFIGURATION
            SQLITEBROWSER_RUNTIME_VERIFY_KIND
            SQLITEBROWSER_RUNTIME_VERIFY_APP_NAME)
        if(NOT DEFINED ${_required_variable}
            OR "${${_required_variable}}" STREQUAL "")
            message(FATAL_ERROR
                "Missing required runtime verification variable: ${_required_variable}")
        endif()
    endforeach()
    _sqlitebrowser_validate_runtime(
        "${SQLITEBROWSER_RUNTIME_VERIFY_DIR}"
        "${SQLITEBROWSER_RUNTIME_VERIFY_CONFIGURATION}"
        "${SQLITEBROWSER_RUNTIME_VERIFY_KIND}"
        "${SQLITEBROWSER_RUNTIME_VERIFY_APP_NAME}")
    return()
endif()

if(DEFINED SQLITEBROWSER_PACKAGE_SOURCE_DIR)
    _sqlitebrowser_assemble_package_runtime()
    return()
endif()

function(_sqlitebrowser_runtime_configuration output_variable)
    if(CMAKE_CONFIGURATION_TYPES)
        list(LENGTH CMAKE_CONFIGURATION_TYPES _configuration_count)
        if(NOT _configuration_count EQUAL 1)
            message(FATAL_ERROR
                "Runtime deployment requires exactly one CMAKE_CONFIGURATION_TYPES entry.")
        endif()
        list(GET CMAKE_CONFIGURATION_TYPES 0 _configuration)
    else()
        set(_configuration "${CMAKE_BUILD_TYPE}")
    endif()

    if(NOT _configuration MATCHES "^(Debug|Release)$")
        message(FATAL_ERROR
            "Runtime deployment supports only Debug and Release; actual: ${_configuration}")
    endif()
    set(${output_variable} "${_configuration}" PARENT_SCOPE)
endfunction()

function(sqlitebrowser_configure_windows_runtime)
    cmake_parse_arguments(PARSE_ARGV 0 RUNTIME
        ""
        "TARGET;SQLCIPHER_TARGET"
        "")

    if(NOT TARGET "${RUNTIME_TARGET}")
        message(FATAL_ERROR "Runtime deployment application target does not exist.")
    endif()
    if(NOT TARGET "${RUNTIME_SQLCIPHER_TARGET}")
        message(FATAL_ERROR "Runtime deployment SQLCipher target does not exist.")
    endif()
    foreach(_required_target IN ITEMS
            OpenSSL::Crypto
            OpenSSL::SSL
            Qt6::windeployqt)
        if(NOT TARGET "${_required_target}")
            message(FATAL_ERROR
                "Runtime deployment target does not exist: ${_required_target}")
        endif()
    endforeach()
    if(NOT DEFINED OPENSSL_RUNTIME_DIR
        OR NOT IS_DIRECTORY "${OPENSSL_RUNTIME_DIR}")
        message(FATAL_ERROR
            "Runtime deployment requires a valid OPENSSL_RUNTIME_DIR.")
    endif()

    set(_brotli_runtime_files)
    foreach(_brotli_name IN ITEMS
            brotlicommon.dll
            brotlidec.dll
            brotlienc.dll)
        set(_brotli_path "${OPENSSL_RUNTIME_DIR}/${_brotli_name}")
        if(NOT EXISTS "${_brotli_path}")
            message(FATAL_ERROR
                "Required OpenSSL Brotli runtime is missing: ${_brotli_path}")
        endif()
        list(APPEND _brotli_runtime_files "${_brotli_path}")
    endforeach()

    _sqlitebrowser_runtime_configuration(_runtime_configuration)
    if(_runtime_configuration STREQUAL "Debug")
        set(_windeployqt_arguments
            --debug
            --no-compiler-runtime
            --force-openssl)
    else()
        set(_windeployqt_arguments
            --release
            --compiler-runtime
            --force-openssl)
    endif()

    set(_visual_studio_vc_dir "${CMAKE_GENERATOR_INSTANCE}/VC/")
    set(_runtime_helper "${CMAKE_CURRENT_FUNCTION_LIST_FILE}")

    add_custom_command(TARGET "${RUNTIME_TARGET}" POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E make_directory
            "$<TARGET_FILE_DIR:${RUNTIME_TARGET}>"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "$<TARGET_FILE:${RUNTIME_SQLCIPHER_TARGET}>"
            "$<TARGET_FILE_DIR:${RUNTIME_TARGET}>"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "$<TARGET_FILE:OpenSSL::Crypto>"
            "$<TARGET_FILE_DIR:${RUNTIME_TARGET}>"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "$<TARGET_FILE:OpenSSL::SSL>"
            "$<TARGET_FILE_DIR:${RUNTIME_TARGET}>"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            ${_brotli_runtime_files}
            "$<TARGET_FILE_DIR:${RUNTIME_TARGET}>"
        COMMAND "${CMAKE_COMMAND}" -E env
            "VCINSTALLDIR=${_visual_studio_vc_dir}"
            "$<TARGET_FILE:Qt6::windeployqt>"
            ${_windeployqt_arguments}
            --dir "$<TARGET_FILE_DIR:${RUNTIME_TARGET}>"
            "$<TARGET_FILE:${RUNTIME_TARGET}>"
        COMMAND "${CMAKE_COMMAND}"
            "-DSQLITEBROWSER_RUNTIME_VERIFY_DIR=$<TARGET_FILE_DIR:${RUNTIME_TARGET}>"
            "-DSQLITEBROWSER_RUNTIME_VERIFY_CONFIGURATION=${_runtime_configuration}"
            "-DSQLITEBROWSER_RUNTIME_VERIFY_KIND=DEVELOPMENT"
            "-DSQLITEBROWSER_RUNTIME_VERIFY_APP_NAME=$<TARGET_FILE_NAME:${RUNTIME_TARGET}>"
            -P "${_runtime_helper}"
        COMMENT
            "Deploying and validating the SQLiteBrowser ${_runtime_configuration} development runtime"
        VERBATIM
        COMMAND_EXPAND_LISTS)

    message(STATUS
        "SQLiteBrowser development runtime: ${_runtime_configuration} -> "
        "$<TARGET_FILE_DIR:${RUNTIME_TARGET}>")
endfunction()

function(sqlitebrowser_add_windows_package_runtime)
    cmake_parse_arguments(PARSE_ARGV 0 PACKAGE
        ""
        "TARGET;RUNTIME_DIR;MANIFEST"
        "")

    if(NOT TARGET "${PACKAGE_TARGET}")
        message(FATAL_ERROR "Package runtime application target does not exist.")
    endif()
    foreach(_required_argument IN ITEMS RUNTIME_DIR MANIFEST)
        if(PACKAGE_${_required_argument} STREQUAL "")
            message(FATAL_ERROR
                "Package runtime requires ${_required_argument}.")
        endif()
    endforeach()

    _sqlitebrowser_runtime_configuration(_runtime_configuration)
    set(_runtime_helper "${CMAKE_CURRENT_FUNCTION_LIST_FILE}")

    add_custom_target(sqlitebrowser_package_runtime
        COMMAND "${CMAKE_COMMAND}"
            "-DSQLITEBROWSER_PACKAGE_CONFIGURATION_ROOT=${SQLITEBROWSER_CONFIGURATION_ROOT}"
            "-DSQLITEBROWSER_PACKAGE_SOURCE_DIR=$<TARGET_FILE_DIR:${PACKAGE_TARGET}>"
            "-DSQLITEBROWSER_PACKAGE_RUNTIME_DIR=${PACKAGE_RUNTIME_DIR}"
            "-DSQLITEBROWSER_PACKAGE_MANIFEST=${PACKAGE_MANIFEST}"
            "-DSQLITEBROWSER_PACKAGE_CONFIGURATION=${_runtime_configuration}"
            "-DSQLITEBROWSER_PACKAGE_APP_NAME=$<TARGET_FILE_NAME:${PACKAGE_TARGET}>"
            -P "${_runtime_helper}"
        DEPENDS "${PACKAGE_TARGET}"
        COMMENT
            "Assembling the strict SQLiteBrowser ${_runtime_configuration} package runtime"
        VERBATIM)
    set_target_properties(sqlitebrowser_package_runtime PROPERTIES
        FOLDER "Packaging")
    message(STATUS
        "SQLiteBrowser package runtime: ${_runtime_configuration} -> "
        "${PACKAGE_RUNTIME_DIR}")
endfunction()

function(sqlitebrowser_add_windows_runtime_smoke)
    cmake_parse_arguments(PARSE_ARGV 0 SMOKE
        ""
        "APP_TARGET;SQLCIPHER_TARGET;SOURCE;TLS_URL;RUNTIME_DIR;RUNTIME_TARGET"
        "")

    if(NOT TARGET "${SMOKE_APP_TARGET}")
        message(FATAL_ERROR "Runtime smoke application target does not exist.")
    endif()
    if(NOT TARGET "${SMOKE_SQLCIPHER_TARGET}")
        message(FATAL_ERROR "Runtime smoke SQLCipher target does not exist.")
    endif()
    if(NOT TARGET "${SMOKE_RUNTIME_TARGET}")
        message(FATAL_ERROR "Runtime smoke package target does not exist.")
    endif()
    if(NOT EXISTS "${SMOKE_SOURCE}")
        message(FATAL_ERROR "Runtime smoke source does not exist: ${SMOKE_SOURCE}")
    endif()
    if(SMOKE_TLS_URL STREQUAL "")
        message(FATAL_ERROR "Runtime smoke TLS URL must not be empty.")
    endif()
    if(SMOKE_RUNTIME_DIR STREQUAL "")
        message(FATAL_ERROR "Runtime smoke directory must not be empty.")
    endif()

    set(_smoke_output_dir
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/build/tests/runtime-smoke")
    set(_smoke_tool sqlitebrowser-runtime-smoke-tool)
    add_executable(${_smoke_tool} EXCLUDE_FROM_ALL "${SMOKE_SOURCE}")
    set_target_properties(${_smoke_tool} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY_DEBUG "${_smoke_output_dir}"
        RUNTIME_OUTPUT_DIRECTORY_RELEASE "${_smoke_output_dir}"
        PDB_OUTPUT_DIRECTORY_DEBUG "${_smoke_output_dir}"
        PDB_OUTPUT_DIRECTORY_RELEASE "${_smoke_output_dir}"
        FOLDER "Tests/Runtime")
    target_link_libraries(${_smoke_tool}
        PRIVATE
            Qt6::Core
            Qt6::Network
            ${SMOKE_SQLCIPHER_TARGET}
            OpenSSL::Crypto)
    target_compile_definitions(${_smoke_tool} PRIVATE SQLITE_HAS_CODEC)

    set(_smoke_script
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/RunSQLiteBrowserWindowsSmoke.cmake")
    add_custom_target(sqlitebrowser_runtime_smoke
        COMMAND "${CMAKE_COMMAND}"
            "-DAPP_EXECUTABLE=${SMOKE_RUNTIME_DIR}/$<TARGET_FILE_NAME:${SMOKE_APP_TARGET}>"
            "-DSMOKE_EXECUTABLE=$<TARGET_FILE:${_smoke_tool}>"
            "-DRUNTIME_DIR=${SMOKE_RUNTIME_DIR}"
            "-DSMOKE_WORK_DIR=${_smoke_output_dir}/work"
            "-DTLS_URL=${SMOKE_TLS_URL}"
            -P "${_smoke_script}"
        DEPENDS
            "${SMOKE_RUNTIME_TARGET}"
            "${_smoke_tool}"
        COMMENT
            "Running restricted-PATH package startup, database, Brotli and TLS smoke tests"
        VERBATIM)
    set_target_properties(sqlitebrowser_runtime_smoke PROPERTIES
        FOLDER "Tests/Runtime")
endfunction()
