if(sqlcipher)
    set_target_properties(${PROJECT_NAME} PROPERTIES OUTPUT_NAME "DB Browser for SQLCipher")
else()
    set_target_properties(${PROJECT_NAME} PROPERTIES OUTPUT_NAME "DB Browser for SQLite")
endif()

if(NOT DEFINED OPENSSL_ROOT_DIR OR OPENSSL_ROOT_DIR STREQUAL "")
    message(FATAL_ERROR "OPENSSL_ROOT_DIR must point to the configuration-specific OpenSSL stage.")
endif()

file(REAL_PATH "${OPENSSL_ROOT_DIR}" OPENSSL_ROOT_DIR)
set(OPENSSL_USE_STATIC_LIBS OFF)
find_package(OpenSSL 3.5.7 EXACT CONFIG REQUIRED)

if(NOT TARGET OpenSSL::Crypto OR NOT TARGET OpenSSL::SSL)
    message(FATAL_ERROR "The selected OpenSSL package must provide OpenSSL::Crypto and OpenSSL::SSL.")
endif()

if(NOT DEFINED OPENSSL_RUNTIME_DIR OR NOT IS_DIRECTORY "${OPENSSL_RUNTIME_DIR}")
    message(FATAL_ERROR "The selected OpenSSL package does not provide a valid OPENSSL_RUNTIME_DIR.")
endif()

file(REAL_PATH "${OPENSSL_RUNTIME_DIR}/.." _openssl_exported_root)
if(NOT _openssl_exported_root STREQUAL OPENSSL_ROOT_DIR)
    message(FATAL_ERROR
        "OpenSSL_DIR and OPENSSL_ROOT_DIR select different stages: "
        "${_openssl_exported_root} vs ${OPENSSL_ROOT_DIR}")
endif()

set(_openssl_manifest "${OPENSSL_ROOT_DIR}/build-manifest.txt")
if(NOT EXISTS "${_openssl_manifest}")
    message(FATAL_ERROR "OpenSSL manifest not found: ${_openssl_manifest}")
endif()

function(_openssl_manifest_value label output_variable)
    file(STRINGS "${_openssl_manifest}" _matching_lines REGEX "^${label}:")
    if(NOT _matching_lines)
        message(FATAL_ERROR
            "OpenSSL manifest does not contain the required '${label}' entry.")
    endif()
    list(GET _matching_lines 0 _matching_line)
    string(REGEX REPLACE "^${label}:[ \t]*" "" _value "${_matching_line}")
    string(STRIP "${_value}" _value)
    set(${output_variable} "${_value}" PARENT_SCOPE)
endfunction()

_openssl_manifest_value("OpenSSL tag" _openssl_tag)
_openssl_manifest_value("Configuration" _openssl_configuration)
_openssl_manifest_value("Configure target" _openssl_target)
_openssl_manifest_value("Windows SDK" _openssl_sdk)

string(REGEX REPLACE "[\\/]+$" "" _openssl_sdk "${_openssl_sdk}")
string(STRIP "${_openssl_sdk}" _openssl_sdk)

if(CMAKE_CONFIGURATION_TYPES)
    list(GET CMAKE_CONFIGURATION_TYPES 0 _openssl_expected_configuration)
else()
    set(_openssl_expected_configuration "${CMAKE_BUILD_TYPE}")
endif()
string(TOLOWER "${_openssl_expected_configuration}" _openssl_expected_configuration)

if(NOT _openssl_tag STREQUAL "openssl-3.5.7")
    message(FATAL_ERROR
        "OpenSSL tag mismatch: expected openssl-3.5.7, manifest reports ${_openssl_tag}.")
endif()

if(NOT _openssl_configuration STREQUAL _openssl_expected_configuration)
    message(FATAL_ERROR
        "OpenSSL configuration mismatch: expected ${_openssl_expected_configuration}, "
        "manifest reports ${_openssl_configuration}.")
endif()

if(NOT _openssl_target STREQUAL "VC-WIN64A")
    message(FATAL_ERROR
        "OpenSSL VC-WIN64A is required; manifest reports ${_openssl_target}.")
endif()

file(STRINGS "${_openssl_manifest}" _openssl_compiler_line REGEX "^compiler:")
if(_openssl_expected_configuration STREQUAL "debug")
    if(NOT _openssl_compiler_line MATCHES "(^|[ \t])/MDd([ \t]|$)")
        message(FATAL_ERROR "The Debug OpenSSL manifest does not report the /MDd CRT.")
    endif()
else()
    if(NOT _openssl_compiler_line MATCHES "(^|[ \t])/MD([ \t]|$)")
        message(FATAL_ERROR "The Release OpenSSL manifest does not report the /MD CRT.")
    endif()
endif()

if(NOT _openssl_sdk STREQUAL CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION)
    string(CONCAT _openssl_sdk_message
        "OpenSSL was built with Windows SDK ${_openssl_sdk}, but the application targets "
        "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}.")
    if(SQLITEBROWSER_DEPENDENCY_SDK_POLICY STREQUAL "STRICT")
        message(FATAL_ERROR "${_openssl_sdk_message}")
    else()
        message(WARNING "${_openssl_sdk_message}")
    endif()
endif()

message(STATUS "OpenSSL package:")
message(STATUS "  Version: ${OpenSSL_VERSION}")
message(STATUS "  Root: ${OPENSSL_ROOT_DIR}")
message(STATUS "  Configuration: ${_openssl_configuration}")
message(STATUS "  Runtime: ${OPENSSL_RUNTIME_DIR}")

if(MSVC)
    target_sources(${PROJECT_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/winapp.rc")
elseif(MINGW)
    # resource compilation for MinGW
    add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/sqlbicon.o"
        COMMAND windres "-I${CMAKE_CURRENT_BINARY_DIR}" "-i${CMAKE_CURRENT_SOURCE_DIR}/src/winapp.rc" -o "${CMAKE_CURRENT_BINARY_DIR}/sqlbicon.o" VERBATIM
    )
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-subsystem,windows")
    target_sources(${PROJECT_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/sqlbicon.o")
endif()
