cmake_minimum_required(VERSION 3.22)

project(sqlitebrowser_brotli
    VERSION 1.2.0
    DESCRIPTION "SQLiteBrowser Windows x64 shared Brotli dependency"
    LANGUAGES C
)

if(NOT WIN32)
    message(FATAL_ERROR "This Brotli wrapper only supports Windows.")
endif()

if(NOT MSVC)
    message(FATAL_ERROR "This Brotli wrapper requires the Visual Studio 2022 MSVC toolchain.")
endif()

if(MSVC_VERSION LESS 1930 OR MSVC_VERSION GREATER_EQUAL 1950)
    message(FATAL_ERROR
        "Unsupported MSVC version ${MSVC_VERSION}. Visual Studio 2022 is required."
    )
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "This Brotli wrapper only supports x64 builds.")
endif()

set(BROTLI_WINDOWS_SDK_VERSION "10.0.22621.0" CACHE STRING
    "Windows SDK version required by the SQLiteBrowser dependency build"
)

if(DEFINED CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION
        AND NOT CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION STREQUAL ""
        AND NOT CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION STREQUAL BROTLI_WINDOWS_SDK_VERSION)
    message(FATAL_ERROR
        "Windows SDK ${BROTLI_WINDOWS_SDK_VERSION} is required, but CMake selected "
        "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}."
    )
endif()

set(BROTLI_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/src")

if(NOT EXISTS "${BROTLI_SOURCE_DIR}/CMakeLists.txt"
        OR NOT EXISTS "${BROTLI_SOURCE_DIR}/c/include/brotli/encode.h"
        OR NOT EXISTS "${BROTLI_SOURCE_DIR}/c/include/brotli/decode.h")
    message(FATAL_ERROR
        "The Brotli submodule is incomplete. Run: git submodule update --init --recursive"
    )
endif()

if(CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_CONFIGURATION_TYPES "Debug;Release" CACHE STRING
        "Supported Brotli configurations" FORCE
    )
elseif(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Brotli build type" FORCE)
elseif(NOT CMAKE_BUILD_TYPE MATCHES "^(Debug|Release)$")
    message(FATAL_ERROR "Only Debug and Release configurations are supported.")
endif()

# Keep the CRT compatible with the rest of the VS2022 dependency stack:
# /MDd for Debug and /MD for Release.
set(CMAKE_MSVC_RUNTIME_LIBRARY
    "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
    CACHE STRING "MSVC runtime used by Brotli" FORCE
)

set(CMAKE_INSTALL_BINDIR "bin" CACHE PATH "Runtime install directory" FORCE)
set(CMAKE_INSTALL_LIBDIR "lib" CACHE PATH "Library install directory" FORCE)
set(CMAKE_INSTALL_INCLUDEDIR "include" CACHE PATH "Header install directory" FORCE)
set(CMAKE_INSTALL_MANDIR "share/man" CACHE PATH "Manual-page install directory" FORCE)

# Reuse the upstream targets while pinning this repository's supported surface:
# three shared libraries only, with no static package variants or CLI tools.
set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared libraries" FORCE)
set(BROTLI_BUILD_FOR_PACKAGE OFF CACHE BOOL "Do not build static package variants" FORCE)
set(BROTLI_BUILD_TOOLS OFF CACHE BOOL "Do not build the Brotli CLI" FORCE)
set(BROTLI_DISABLE_TESTS ON CACHE BOOL "Disable upstream CLI-based tests" FORCE)

# add_subdirectory() makes upstream default this to ON, which suppresses its
# install rules. Force it OFF so cmake --install creates the dependency stage.
set(BROTLI_BUNDLED_MODE OFF CACHE BOOL "Enable the upstream install rules" FORCE)

enable_testing()

add_subdirectory(
    "${BROTLI_SOURCE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}/upstream"
)

foreach(_brotli_target IN ITEMS brotlicommon brotlidec brotlienc)
    if(NOT TARGET ${_brotli_target})
        message(FATAL_ERROR "The upstream CMake project did not create ${_brotli_target}.")
    endif()

    get_target_property(_brotli_target_type ${_brotli_target} TYPE)
    if(NOT _brotli_target_type STREQUAL "SHARED_LIBRARY")
        message(FATAL_ERROR
            "${_brotli_target} must be a shared library, got ${_brotli_target_type}."
        )
    endif()

    # Debug and Release are isolated by stage directory, so keep the upstream
    # DLL/import-library names stable across configurations.
    set_target_properties(${_brotli_target} PROPERTIES DEBUG_POSTFIX "")

    # Keep Release optimized while producing linker PDBs for crash analysis.
    # Debug already receives /Zi and /DEBUG from CMake's MSVC defaults.
    target_compile_options(${_brotli_target} PRIVATE
        "$<$<CONFIG:Release>:/Zi>"
    )
    target_link_options(${_brotli_target} PRIVATE
        "$<$<CONFIG:Release>:/DEBUG:FULL>"
        "$<$<CONFIG:Release>:/OPT:REF>"
        "$<$<CONFIG:Release>:/OPT:ICF>"
    )

    # Install only the linker PDB matching each DLL. Compiler intermediates
    # such as vc143.pdb remain in work and must never enter the dependency stage.
    install(FILES "$<TARGET_PDB_FILE:${_brotli_target}>"
        DESTINATION "${CMAKE_INSTALL_BINDIR}"
        CONFIGURATIONS Debug Release
    )
endforeach()

foreach(_forbidden_target IN ITEMS
        brotlicommon-static
        brotlidec-static
        brotlienc-static
        brotli)
    if(TARGET ${_forbidden_target})
        message(FATAL_ERROR "Unexpected disabled Brotli target: ${_forbidden_target}.")
    endif()
endforeach()

add_executable(brotli_shared_smoke EXCLUDE_FROM_ALL
    "${CMAKE_CURRENT_LIST_DIR}/tests/brotli_smoke.c"
)

target_link_libraries(brotli_shared_smoke PRIVATE brotlienc brotlidec)

set_target_properties(brotli_shared_smoke PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED YES
    C_EXTENSIONS NO
    DEBUG_POSTFIX ""
)

add_test(NAME brotli.shared.smoke COMMAND "$<TARGET_FILE:brotli_shared_smoke>")

# The executable and the three DLLs can be generated in different directories.
# Prepending every runtime target directory also documents the complete runtime
# contract and proves that the smoke test consumes the shared artifacts.
set_tests_properties(brotli.shared.smoke PROPERTIES
    LABELS "smoke;shared"
    ENVIRONMENT_MODIFICATION
        "PATH=path_list_prepend:$<TARGET_FILE_DIR:brotlicommon>"
        "PATH=path_list_prepend:$<TARGET_FILE_DIR:brotlidec>"
        "PATH=path_list_prepend:$<TARGET_FILE_DIR:brotlienc>"
)

install(FILES "${BROTLI_SOURCE_DIR}/LICENSE"
    DESTINATION "share/licenses/brotli"
)

message(STATUS "Brotli source: ${BROTLI_SOURCE_DIR}")
message(STATUS "Brotli libraries: brotlicommon.dll; brotlidec.dll; brotlienc.dll")
message(STATUS "Brotli static libraries: disabled")
message(STATUS "Brotli CLI and upstream CLI tests: disabled")
message(STATUS "Brotli Windows SDK: ${BROTLI_WINDOWS_SDK_VERSION}")
