include_guard(GLOBAL)

if(DEFINED SQLITEBROWSER_RUNTIME_VERIFY_DIR)
    if(NOT SQLITEBROWSER_RUNTIME_VERIFY_CONFIGURATION MATCHES "^(Debug|Release)$")
        message(FATAL_ERROR
            "SQLITEBROWSER_RUNTIME_VERIFY_CONFIGURATION must be Debug or Release.")
    endif()

    file(TO_CMAKE_PATH "${SQLITEBROWSER_RUNTIME_VERIFY_DIR}" _runtime_dir)
    if(SQLITEBROWSER_RUNTIME_VERIFY_CONFIGURATION STREQUAL "Debug")
        set(_qt_suffix "d")
    else()
        set(_qt_suffix "")
    endif()

    set(_required_runtime_files
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
        "opengl32sw.dll"
        "platforms/qwindows${_qt_suffix}.dll"
        "tls/qopensslbackend${_qt_suffix}.dll"
        "tls/qschannelbackend${_qt_suffix}.dll"
        "imageformats/qsvg${_qt_suffix}.dll"
        "iconengines/qsvgicon${_qt_suffix}.dll"
        "styles/qmodernwindowsstyle${_qt_suffix}.dll"
    )
    if(SQLITEBROWSER_RUNTIME_VERIFY_CONFIGURATION STREQUAL "Release")
        list(APPEND _required_runtime_files "vc_redist.x64.exe")
    endif()

    set(_runtime_errors)
    foreach(_relative_path IN LISTS _required_runtime_files)
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

    # This is the unified development bin, not the package runtime. Dependency
    # import libraries and linker PDBs, plus the optional zlib/zstd products,
    # are valid here. Packaging uses a separate strict runtime allowlist.
    set(_forbidden_runtime_files
        "openssl.exe"
        "sqlcipher.exe"
        "vc143.pdb"
    )
    foreach(_relative_path IN LISTS _forbidden_runtime_files)
        if(EXISTS "${_runtime_dir}/${_relative_path}")
            list(APPEND _runtime_errors "unexpected: ${_relative_path}")
        endif()
    endforeach()

    if(SQLITEBROWSER_RUNTIME_VERIFY_CONFIGURATION STREQUAL "Release")
        file(GLOB _debug_qt_libraries LIST_DIRECTORIES FALSE
            "${_runtime_dir}/Qt6*d.dll")
        foreach(_debug_plugin IN ITEMS
                "platforms/qwindowsd.dll"
                "tls/qopensslbackendd.dll"
                "tls/qschannelbackendd.dll")
            if(EXISTS "${_runtime_dir}/${_debug_plugin}")
                list(APPEND _debug_qt_libraries "${_runtime_dir}/${_debug_plugin}")
            endif()
        endforeach()
        foreach(_debug_file IN LISTS _debug_qt_libraries)
            file(RELATIVE_PATH _relative_debug_file "${_runtime_dir}" "${_debug_file}")
            list(APPEND _runtime_errors "unexpected Debug Qt runtime: ${_relative_debug_file}")
        endforeach()
    else()
        foreach(_release_file IN ITEMS
                "Qt6Core.dll"
                "Qt6Gui.dll"
                "Qt6Network.dll"
                "Qt6Widgets.dll"
                "platforms/qwindows.dll"
                "tls/qopensslbackend.dll")
            if(EXISTS "${_runtime_dir}/${_release_file}")
                list(APPEND _runtime_errors
                    "unexpected Release Qt runtime: ${_release_file}")
            endif()
        endforeach()
    endif()

    if(_runtime_errors)
        list(JOIN _runtime_errors "\n  " _runtime_error_text)
        message(FATAL_ERROR
            "SQLiteBrowser runtime validation failed in ${_runtime_dir}:\n"
            "  ${_runtime_error_text}")
    endif()

    message(STATUS
        "SQLiteBrowser ${SQLITEBROWSER_RUNTIME_VERIFY_CONFIGURATION} runtime "
        "validated: ${_runtime_dir}")
    return()
endif()

include(CMakeParseArguments)

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
            -P "${_runtime_helper}"
        COMMENT
            "Deploying and validating the SQLiteBrowser ${_runtime_configuration} runtime"
        VERBATIM
        COMMAND_EXPAND_LISTS
    )

    message(STATUS
        "SQLiteBrowser runtime deployment: ${_runtime_configuration} -> "
        "$<TARGET_FILE_DIR:${RUNTIME_TARGET}>")
endfunction()

function(sqlitebrowser_add_windows_runtime_smoke)
    cmake_parse_arguments(PARSE_ARGV 0 SMOKE
        ""
        "APP_TARGET;SQLCIPHER_TARGET;SOURCE;TLS_URL"
        "")

    if(NOT TARGET "${SMOKE_APP_TARGET}")
        message(FATAL_ERROR "Runtime smoke application target does not exist.")
    endif()
    if(NOT TARGET "${SMOKE_SQLCIPHER_TARGET}")
        message(FATAL_ERROR "Runtime smoke SQLCipher target does not exist.")
    endif()
    if(NOT EXISTS "${SMOKE_SOURCE}")
        message(FATAL_ERROR "Runtime smoke source does not exist: ${SMOKE_SOURCE}")
    endif()
    if(SMOKE_TLS_URL STREQUAL "")
        message(FATAL_ERROR "Runtime smoke TLS URL must not be empty.")
    endif()

    set(_smoke_tool sqlitebrowser-runtime-smoke-tool)
    add_executable(${_smoke_tool} EXCLUDE_FROM_ALL "${SMOKE_SOURCE}")
    set_target_properties(${_smoke_tool} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/tests"
        RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/tests"
        FOLDER "Tests"
    )
    target_link_libraries(${_smoke_tool}
        PRIVATE
            Qt6::Core
            Qt6::Network
            ${SMOKE_SQLCIPHER_TARGET}
            OpenSSL::Crypto
    )
    target_compile_definitions(${_smoke_tool} PRIVATE SQLITE_HAS_CODEC)

    set(_smoke_script
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/RunSQLiteBrowserWindowsSmoke.cmake")
    add_custom_target(sqlitebrowser_runtime_smoke
        COMMAND "${CMAKE_COMMAND}"
            "-DAPP_EXECUTABLE=$<TARGET_FILE:${SMOKE_APP_TARGET}>"
            "-DSMOKE_EXECUTABLE=$<TARGET_FILE:${_smoke_tool}>"
            "-DRUNTIME_DIR=$<TARGET_FILE_DIR:${SMOKE_APP_TARGET}>"
            "-DSMOKE_WORK_DIR=${CMAKE_BINARY_DIR}/runtime-smoke"
            "-DTLS_URL=${SMOKE_TLS_URL}"
            -P "${_smoke_script}"
        DEPENDS "${SMOKE_APP_TARGET}" "${_smoke_tool}"
        COMMENT
            "Running restricted-PATH startup, database, Brotli and TLS smoke tests"
        VERBATIM
    )
endfunction()
