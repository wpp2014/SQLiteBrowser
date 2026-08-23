cmake_minimum_required(VERSION 3.21)

project(sqlitebrowser_sqlcipher
    VERSION 4.18.0
    DESCRIPTION "SQLiteBrowser SQLCipher Windows build wrapper"
    LANGUAGES C
)

if(NOT WIN32)
    message(FATAL_ERROR "This SQLCipher wrapper supports Windows only.")
endif()

if(NOT MSVC)
    message(FATAL_ERROR "This SQLCipher wrapper requires the Visual Studio 2022 MSVC toolchain.")
endif()

if(MSVC_VERSION LESS 1930 OR MSVC_VERSION GREATER_EQUAL 1950)
    message(FATAL_ERROR "Expected the Visual Studio 2022 MSVC toolchain, got MSVC_VERSION=${MSVC_VERSION}.")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "This SQLCipher wrapper supports Windows x64 only.")
endif()

if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build configuration" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS Debug Release)
endif()

get_filename_component(SQLITEBROWSER_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(SQLCIPHER_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/src")

set(SQLCIPHER_EXPECTED_TAG "v4.18.0" CACHE STRING "Expected SQLCipher tag")
set(SQLCIPHER_EXPECTED_COMMIT
    "63697beb0fafcb61faa7a3e6fd267036548ab11b"
    CACHE STRING "Expected SQLCipher source commit"
)
set(SQLCIPHER_WINDOWS_SDK_VERSION
    "10.0.22621.0"
    CACHE STRING "Windows SDK selected by VsDevCmd"
)
if(DEFINED CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION
   AND NOT CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION STREQUAL SQLCIPHER_WINDOWS_SDK_VERSION)
    message(FATAL_ERROR
        "The generated Visual Studio project selected Windows SDK "
        "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}; expected ${SQLCIPHER_WINDOWS_SDK_VERSION}. "
        "Configure with -DCMAKE_SYSTEM_VERSION=${SQLCIPHER_WINDOWS_SDK_VERSION}."
    )
endif()
set(SQLCIPHER_OPENSSL_ROOT_DEBUG
    "${SQLITEBROWSER_ROOT}/build/openssl/x64-debug/stage"
    CACHE PATH "OpenSSL Debug stage"
)
set(SQLCIPHER_OPENSSL_ROOT_RELEASE
    "${SQLITEBROWSER_ROOT}/build/openssl/x64-release/stage"
    CACHE PATH "OpenSSL Release stage"
)
set(SQLCIPHER_STAGE_ROOT
    "${SQLITEBROWSER_ROOT}/build/sqlcipher"
    CACHE PATH "SQLCipher work and stage root"
)
set(SQLCIPHER_EXTRA_DEFINITIONS
    ""
    CACHE STRING "Additional audited compiler definitions, written as space-separated -D options"
)
option(SQLCIPHER_BUILD_CLI "Build and verify sqlcipher.exe" ON)

if(NOT EXISTS "${SQLCIPHER_SOURCE_DIR}/Makefile.msc"
   OR NOT EXISTS "${SQLCIPHER_SOURCE_DIR}/src/sqlcipher.c")
    message(FATAL_ERROR
        "The SQLCipher submodule is not initialized at ${SQLCIPHER_SOURCE_DIR}. "
        "Run git submodule update --init --recursive."
    )
endif()

set(_vs_root "")
set(_vs_edition "")
foreach(_edition IN ITEMS Enterprise Professional Community)
    set(_candidate "C:/Program Files/Microsoft Visual Studio/2022/${_edition}")
    if(NOT _vs_root AND EXISTS "${_candidate}/Common7/Tools/VsDevCmd.bat")
        set(_vs_root "${_candidate}")
        set(_vs_edition "${_edition}")
    endif()
endforeach()

if(NOT _vs_root)
    message(FATAL_ERROR
        "Visual Studio 2022 was not found in the supported Enterprise, Professional, "
        "or Community default installation directories."
    )
endif()

set(_vs_devcmd "${_vs_root}/Common7/Tools/VsDevCmd.bat")
set(_sqlcipher_definitions
    "-DSQLITE_HAS_CODEC=1 "
    "-DSQLITE_TEMP_STORE=2 "
    "-DSQLITE_EXTRA_INIT=sqlcipher_extra_init "
    "-DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown "
    "-DSQLCIPHER_CRYPTO_OPENSSL=1 "
    "-DSQLITE_ENABLE_FTS3=1 "
    "-DSQLITE_ENABLE_FTS5=1 "
    "-DSQLITE_ENABLE_FTS3_PARENTHESIS=1 "
    "-DSQLITE_ENABLE_STAT4=1 "
    "-DSQLITE_SOUNDEX=1 "
    "-DSQLITE_ENABLE_JSON1=1 "
    "-DSQLITE_ENABLE_GEOPOLY=1 "
    "-DSQLITE_ENABLE_RTREE=1 "
    "-DSQLITE_ENABLE_MATH_FUNCTIONS=1 "
    "-DSQLITE_MAX_ATTACHED=125"
)
string(CONCAT _sqlcipher_definitions ${_sqlcipher_definitions})
if(SQLCIPHER_EXTRA_DEFINITIONS)
    string(APPEND _sqlcipher_definitions " ${SQLCIPHER_EXTRA_DEFINITIONS}")
endif()

set(_build_helper "${CMAKE_CURRENT_LIST_DIR}/cmake/BuildSQLCipher.cmake")
if(NOT EXISTS "${_build_helper}")
    message(FATAL_ERROR "Missing SQLCipher build helper: ${_build_helper}")
endif()

set(_effective_configuration "$<IF:$<CONFIG:Debug>,Debug,Release>")

add_custom_target(sqlcipher_stage ALL
    COMMAND "${CMAKE_COMMAND}"
        "-DSQLCIPHER_CONFIGURATION=${_effective_configuration}"
        "-DSQLCIPHER_SOURCE_DIR=${SQLCIPHER_SOURCE_DIR}"
        "-DSQLCIPHER_STAGE_ROOT=${SQLCIPHER_STAGE_ROOT}"
        "-DSQLCIPHER_OPENSSL_ROOT_DEBUG=${SQLCIPHER_OPENSSL_ROOT_DEBUG}"
        "-DSQLCIPHER_OPENSSL_ROOT_RELEASE=${SQLCIPHER_OPENSSL_ROOT_RELEASE}"
        "-DSQLCIPHER_VS_DEVCMD=${_vs_devcmd}"
        "-DSQLCIPHER_VS_EDITION=${_vs_edition}"
        "-DSQLCIPHER_WINDOWS_SDK_VERSION=${SQLCIPHER_WINDOWS_SDK_VERSION}"
        "-DSQLCIPHER_EXPECTED_TAG=${SQLCIPHER_EXPECTED_TAG}"
        "-DSQLCIPHER_EXPECTED_COMMIT=${SQLCIPHER_EXPECTED_COMMIT}"
        "-DSQLCIPHER_DEFINITIONS=${_sqlcipher_definitions}"
        "-DSQLCIPHER_BUILD_CLI=${SQLCIPHER_BUILD_CLI}"
        -P "${_build_helper}"
    COMMENT "Building and staging SQLCipher ${SQLCIPHER_EXPECTED_TAG} (${_effective_configuration} x64)"
    USES_TERMINAL
    VERBATIM
)

set(_debug_stage "${SQLCIPHER_STAGE_ROOT}/x64-debug/stage")
set(_release_stage "${SQLCIPHER_STAGE_ROOT}/x64-release/stage")

# CMake validates imported include paths while generating consumers. Create only
# the ignored stage directories here; the build helper populates them later.
file(MAKE_DIRECTORY
    "${_debug_stage}/include/sqlcipher"
    "${_release_stage}/include/sqlcipher"
)

add_library(SQLCipher::SQLCipher SHARED IMPORTED GLOBAL)
set_target_properties(SQLCipher::SQLCipher PROPERTIES
    IMPORTED_CONFIGURATIONS "Debug;Release"
    IMPORTED_IMPLIB_DEBUG "${_debug_stage}/lib/sqlcipher.lib"
    IMPORTED_LOCATION_DEBUG "${_debug_stage}/bin/sqlcipher.dll"
    IMPORTED_IMPLIB_RELEASE "${_release_stage}/lib/sqlcipher.lib"
    IMPORTED_LOCATION_RELEASE "${_release_stage}/bin/sqlcipher.dll"
    MAP_IMPORTED_CONFIG_MINSIZEREL Release
    MAP_IMPORTED_CONFIG_RELWITHDEBINFO Release
    INTERFACE_INCLUDE_DIRECTORIES
        "$<IF:$<CONFIG:Debug>,${_debug_stage}/include/sqlcipher,${_release_stage}/include/sqlcipher>"
    INTERFACE_COMPILE_DEFINITIONS "SQLITE_HAS_CODEC;SQLITE_TEMP_STORE=2"
)
add_dependencies(SQLCipher::SQLCipher sqlcipher_stage)

message(STATUS "SQLCipher source: ${SQLCIPHER_SOURCE_DIR}")
message(STATUS "SQLCipher Visual Studio: ${_vs_edition} 2022")
message(STATUS "SQLCipher Windows SDK: ${SQLCIPHER_WINDOWS_SDK_VERSION}")
message(STATUS "SQLCipher Debug OpenSSL: ${SQLCIPHER_OPENSSL_ROOT_DEBUG}")
message(STATUS "SQLCipher Release OpenSSL: ${SQLCIPHER_OPENSSL_ROOT_RELEASE}")
message(STATUS "SQLCipher stage root: ${SQLCIPHER_STAGE_ROOT}")
