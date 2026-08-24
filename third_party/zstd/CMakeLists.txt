cmake_minimum_required(VERSION 3.22)

project(sqlitebrowser_zstd
    VERSION 1.5.7
    DESCRIPTION "SQLiteBrowser Windows x64 shared zstd dependency"
    LANGUAGES C
)

if(NOT WIN32)
    message(FATAL_ERROR "This zstd wrapper only supports Windows.")
endif()

if(NOT MSVC)
    message(FATAL_ERROR "This zstd wrapper requires the Visual Studio 2022 MSVC toolchain.")
endif()

if(MSVC_VERSION LESS 1930 OR MSVC_VERSION GREATER_EQUAL 1950)
    message(FATAL_ERROR
        "Unsupported MSVC version ${MSVC_VERSION}. Visual Studio 2022 is required."
    )
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "This zstd wrapper only supports x64 builds.")
endif()

set(ZSTD_WINDOWS_SDK_VERSION "10.0.22621.0" CACHE STRING
    "Windows SDK version required by the SQLiteBrowser dependency build"
)

if(DEFINED CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION
        AND NOT CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION STREQUAL ""
        AND NOT CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION STREQUAL ZSTD_WINDOWS_SDK_VERSION)
    message(FATAL_ERROR
        "Windows SDK ${ZSTD_WINDOWS_SDK_VERSION} is required, but CMake selected "
        "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}."
    )
endif()

set(ZSTD_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/src")
set(ZSTD_UPSTREAM_CMAKE_DIR "${ZSTD_SOURCE_DIR}/build/cmake")

if(NOT EXISTS "${ZSTD_UPSTREAM_CMAKE_DIR}/CMakeLists.txt"
        OR NOT EXISTS "${ZSTD_SOURCE_DIR}/lib/zstd.h")
    message(FATAL_ERROR
        "The zstd submodule is incomplete. Run: git submodule update --init --recursive"
    )
endif()

if(CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_CONFIGURATION_TYPES "Debug;Release" CACHE STRING
        "Supported zstd configurations" FORCE
    )
elseif(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "zstd build type" FORCE)
elseif(NOT CMAKE_BUILD_TYPE MATCHES "^(Debug|Release)$")
    message(FATAL_ERROR "Only Debug and Release configurations are supported.")
endif()

# Keep the CRT compatible with the rest of the VS2022 dependency stack:
# /MDd for Debug and /MD for Release.
set(CMAKE_MSVC_RUNTIME_LIBRARY
    "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
    CACHE STRING "MSVC runtime used by zstd" FORCE
)

# Keep the install tree consistent with the other bundled dependencies.
set(CMAKE_INSTALL_BINDIR "bin" CACHE PATH "Executable install directory" FORCE)
set(CMAKE_INSTALL_LIBDIR "lib" CACHE PATH "Library install directory" FORCE)
set(CMAKE_INSTALL_INCLUDEDIR "include" CACHE PATH "Header install directory" FORCE)

# Pin the upstream feature surface. This project builds only the shared zstd
# library; CLI programs, contrib code, static libraries, legacy APIs, and all
# optional compatibility backends are intentionally excluded.
set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared libraries" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "Disable upstream tests" FORCE)
set(ZSTD_BUILD_SHARED ON CACHE BOOL "Build the shared zstd library" FORCE)
set(ZSTD_BUILD_STATIC OFF CACHE BOOL "Do not build the static zstd library" FORCE)
set(ZSTD_BUILD_COMPRESSION ON CACHE BOOL "Enable compression APIs" FORCE)
set(ZSTD_BUILD_DECOMPRESSION ON CACHE BOOL "Enable decompression APIs" FORCE)
set(ZSTD_BUILD_DICTBUILDER ON CACHE BOOL "Enable dictionary builder APIs" FORCE)
set(ZSTD_BUILD_DEPRECATED OFF CACHE BOOL "Disable deprecated APIs" FORCE)
set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "Do not build zstd CLI programs" FORCE)
set(ZSTD_BUILD_CONTRIB OFF CACHE BOOL "Do not build contrib projects" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "Do not build upstream static-library tests" FORCE)
set(ZSTD_PROGRAMS_LINK_SHARED OFF CACHE BOOL "CLI linkage policy (CLI is disabled)" FORCE)
set(ZSTD_ZLIB_SUPPORT OFF CACHE BOOL "Do not enable zlib compatibility support" FORCE)
set(ZSTD_LZMA_SUPPORT OFF CACHE BOOL "Do not enable LZMA compatibility support" FORCE)
set(ZSTD_LZ4_SUPPORT OFF CACHE BOOL "Do not enable LZ4 compatibility support" FORCE)
set(ZSTD_MULTITHREAD_SUPPORT ON CACHE BOOL "Enable zstd multithreading" FORCE)
set(ZSTD_LEGACY_SUPPORT OFF CACHE BOOL "Disable legacy frame support" FORCE)
set(ZSTD_USE_STATIC_RUNTIME OFF CACHE BOOL "Use the dynamic MSVC runtime" FORCE)
set(ACTIVATE_MULTITHREADED_COMPILATION ON CACHE BOOL
    "Enable upstream parallel compilation support" FORCE
)

# BUILD_TESTING remains OFF so the upstream static-only suite is not added.
# This wrapper enables CTest separately for its project-owned shared-DLL smoke test.
enable_testing()

add_subdirectory(
    "${ZSTD_UPSTREAM_CMAKE_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}/upstream"
)

if(NOT TARGET libzstd_shared)
    message(FATAL_ERROR "The upstream CMake project did not create libzstd_shared.")
endif()

if(TARGET libzstd_static)
    message(FATAL_ERROR "The static zstd target must remain disabled.")
endif()

# OpenSSL's Windows loader expects libzstd.dll. Keep Debug and Release artifact
# names identical; their separate stage directories prevent collisions.
set_target_properties(libzstd_shared PROPERTIES
    OUTPUT_NAME "libzstd"
    DEBUG_POSTFIX ""
)

# Upstream's multi-config path does not add DEBUGLEVEL automatically.
if(CMAKE_CONFIGURATION_TYPES)
    target_compile_definitions(libzstd_shared PRIVATE
        "$<$<CONFIG:Debug>:DEBUGLEVEL=1>"
    )
endif()

add_executable(zstd_shared_smoke
    "${CMAKE_CURRENT_LIST_DIR}/tests/zstd_smoke.c"
)

target_link_libraries(zstd_shared_smoke PRIVATE libzstd_shared)
target_compile_definitions(zstd_shared_smoke PRIVATE ZSTD_DLL_IMPORT=1)

set_target_properties(zstd_shared_smoke PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED YES
    C_EXTENSIONS NO
    DEBUG_POSTFIX ""
)

add_test(NAME zstd.shared.smoke COMMAND "$<TARGET_FILE:zstd_shared_smoke>")

# The executable and DLL are generated in different subdirectories. Prepending
# the DLL directory proves that the smoke test loads the shared artifact while
# leaving build and install layouts unchanged.
set_tests_properties(zstd.shared.smoke PROPERTIES
    LABELS "smoke;shared"
    ENVIRONMENT_MODIFICATION
        "PATH=path_list_prepend:$<TARGET_FILE_DIR:libzstd_shared>"
)
