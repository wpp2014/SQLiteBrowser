cmake_minimum_required(VERSION 3.21)

project(sqlitebrowser_zlib
    VERSION 1.3.2
    DESCRIPTION "SQLiteBrowser zlib Windows build wrapper"
    LANGUAGES C
)

if(NOT WIN32)
    message(FATAL_ERROR "This zlib wrapper supports Windows only.")
endif()

if(NOT MSVC)
    message(FATAL_ERROR "This zlib wrapper requires the Visual Studio 2022 MSVC toolchain.")
endif()

if(MSVC_VERSION LESS 1930 OR MSVC_VERSION GREATER_EQUAL 1950)
    message(FATAL_ERROR
        "Expected the Visual Studio 2022 MSVC toolchain, got MSVC_VERSION=${MSVC_VERSION}."
    )
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "This zlib wrapper supports Windows x64 only.")
endif()

set(ZLIB_WINDOWS_SDK_VERSION
    "10.0.26100.0"
    CACHE STRING "Required Windows SDK version"
)
if(DEFINED CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION
   AND NOT CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION STREQUAL ZLIB_WINDOWS_SDK_VERSION)
    message(FATAL_ERROR
        "The generated Visual Studio project selected Windows SDK "
        "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}; expected ${ZLIB_WINDOWS_SDK_VERSION}. "
        "Configure with -DCMAKE_SYSTEM_VERSION=${ZLIB_WINDOWS_SDK_VERSION}."
    )
endif()

set(ZLIB_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/src")
if(NOT EXISTS "${ZLIB_SOURCE_DIR}/CMakeLists.txt"
   OR NOT EXISTS "${ZLIB_SOURCE_DIR}/zlib.h")
    message(FATAL_ERROR
        "The zlib submodule is not initialized at ${ZLIB_SOURCE_DIR}. "
        "Run git submodule update --init --recursive."
    )
endif()

if(CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_CONFIGURATION_TYPES
        "Debug;Release"
        CACHE STRING "Supported zlib configurations" FORCE
    )
elseif(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build configuration" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS Debug Release)
endif()

set(CMAKE_MSVC_RUNTIME_LIBRARY
    "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL"
    CACHE STRING "Use the matching dynamic MSVC runtime" FORCE
)

set(CMAKE_INSTALL_BINDIR "bin" CACHE STRING "Runtime install directory" FORCE)
set(CMAKE_INSTALL_LIBDIR "lib" CACHE STRING "Library install directory" FORCE)
set(CMAKE_INSTALL_INCLUDEDIR "include" CACHE STRING "Header install directory" FORCE)

set(ZLIB_BUILD_SHARED ON CACHE BOOL "Build the zlib DLL" FORCE)
set(ZLIB_BUILD_STATIC OFF CACHE BOOL "Do not build static zlib" FORCE)
set(ZLIB_BUILD_TESTING ON CACHE BOOL "Build and register zlib tests" FORCE)
set(ZLIB_INSTALL ON CACHE BOOL "Enable staging through cmake --install" FORCE)
set(ZLIB_PREFIX OFF CACHE BOOL "Do not prefix zlib APIs" FORCE)

foreach(_option IN ITEMS
    ZLIB_BUILD_ADA
    ZLIB_BUILD_BLAST
    ZLIB_BUILD_IOSTREAM3
    ZLIB_BUILD_MINIZIP
    ZLIB_BUILD_PUFF
    ZLIB_BUILD_TESTZLIB
    ZLIB_BUILD_ZLIB1_DLL
    ZLIB_WITH_GVMAT64
    ZLIB_WITH_INFBACK9
    ZLIB_WITH_CRC32VX
)
    set(${_option} OFF CACHE BOOL "Disabled by the SQLiteBrowser zlib wrapper" FORCE)
endforeach()

enable_testing()
add_subdirectory(src)

if(NOT TARGET zlib)
    message(FATAL_ERROR "The expected upstream zlib shared target was not created.")
endif()

set_target_properties(zlib PROPERTIES
    OUTPUT_NAME "zlib1"
    DEBUG_POSTFIX ""
)

# Keep Release optimized while emitting the linker PDB used for crash analysis.
# Compiler PDBs remain in the private work directory.
target_compile_options(zlib PRIVATE
    "$<$<CONFIG:Release>:/Zi>"
)
target_link_options(zlib PRIVATE
    "$<$<CONFIG:Release>:/DEBUG:FULL>"
    "$<$<CONFIG:Release>:/OPT:REF>"
    "$<$<CONFIG:Release>:/OPT:ICF>"
)

install(FILES "$<TARGET_PDB_FILE:zlib>"
    DESTINATION "${CMAKE_INSTALL_BINDIR}"
    CONFIGURATIONS Debug Release
)

message(STATUS "zlib source: ${ZLIB_SOURCE_DIR}")
message(STATUS "zlib output name: zlib1.dll")
message(STATUS "zlib static library: disabled")
message(STATUS "zlib contrib libraries: disabled")
message(STATUS "zlib Windows SDK: ${ZLIB_WINDOWS_SDK_VERSION}")
