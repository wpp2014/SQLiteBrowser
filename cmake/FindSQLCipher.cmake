# - Try to find SQLCipher
# Once done this will define
#
#  SQLCIPHER_FOUND - system has SQLCipher
#  SQLCIPHER_INCLUDE_DIR - the SQLCipher include directory
#  SQLCIPHER_LIBRARIES - Link these to use SQLCipher
#  SQLCIPHER_DEFINITIONS - Compiler switches required for using SQLCipher
#  SQLCIPHER_VERSION - This is set to major.minor.revision (e.g. 3.4.1)
#
# Hints to find SQLCipher
#
#  Set SQLCIPHER_ROOT_DIR to the root directory of a SQLCipher installation
#
# The following variables may be set
#
#  SQLCIPHER_USE_OPENSSL - Set to ON/OFF to specify whether to search and use OpenSSL.
#                          Default is OFF.
#  SQLCIPHER_OPENSSL_USE_ZLIB - Set to ON/OFF to specify whether to search and use Zlib in OpenSSL
#                               Default is OFF.

# Redistribution and use is allowed according to the terms of the BSD license.

# Copyright (c) 2008, Gilles Caulier, <caulier.gilles@gmail.com>
# Copyright (c) 2014, Christian Dávid, <christian-david@web.de>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# The v4 Windows build consumes a configuration-specific staged shared library.
if(WIN32)
  if(NOT DEFINED SQLCIPHER_ROOT_DIR OR SQLCIPHER_ROOT_DIR STREQUAL "")
    message(FATAL_ERROR
      "SQLCIPHER_ROOT_DIR must point to the configuration-specific SQLCipher stage.")
  endif()

  file(REAL_PATH "${SQLCIPHER_ROOT_DIR}" SQLCIPHER_ROOT_DIR)

  find_path(SQLCIPHER_INCLUDE_DIR
    NAMES sqlite3.h
    PATHS "${SQLCIPHER_ROOT_DIR}/include/sqlcipher"
    NO_DEFAULT_PATH)

  find_library(SQLCIPHER_LIBRARY
    NAMES sqlcipher
    PATHS "${SQLCIPHER_ROOT_DIR}/lib"
    NO_DEFAULT_PATH)

  find_file(SQLCIPHER_RUNTIME_LIBRARY
    NAMES sqlcipher.dll
    PATHS "${SQLCIPHER_ROOT_DIR}/bin"
    NO_DEFAULT_PATH)

  set(SQLCIPHER_MANIFEST "${SQLCIPHER_ROOT_DIR}/build-manifest.txt")
  set(SQLCIPHER_VERSION "4.18.0")

  include(FindPackageHandleStandardArgs)
  find_package_handle_standard_args(SQLCipher
    REQUIRED_VARS
      SQLCIPHER_INCLUDE_DIR
      SQLCIPHER_LIBRARY
      SQLCIPHER_RUNTIME_LIBRARY
      SQLCIPHER_MANIFEST
    VERSION_VAR SQLCIPHER_VERSION)

  if(NOT EXISTS "${SQLCIPHER_MANIFEST}")
    message(FATAL_ERROR "SQLCipher manifest not found: ${SQLCIPHER_MANIFEST}")
  endif()

  function(_sqlcipher_manifest_value label output_variable)
    file(STRINGS "${SQLCIPHER_MANIFEST}" _matching_lines REGEX "^${label}:")
    if(NOT _matching_lines)
      message(FATAL_ERROR
        "SQLCipher manifest does not contain the required '${label}' entry.")
    endif()
    list(GET _matching_lines 0 _matching_line)
    string(REGEX REPLACE "^${label}:[ \t]*" "" _value "${_matching_line}")
    string(STRIP "${_value}" _value)
    set(${output_variable} "${_value}" PARENT_SCOPE)
  endfunction()

  if(CMAKE_CONFIGURATION_TYPES)
    list(LENGTH CMAKE_CONFIGURATION_TYPES _configuration_count)
    if(NOT _configuration_count EQUAL 1)
      message(FATAL_ERROR
        "The SQLCipher stage build requires exactly one CMAKE_CONFIGURATION_TYPES entry.")
    endif()
    list(GET CMAKE_CONFIGURATION_TYPES 0 _expected_configuration)
  else()
    set(_expected_configuration "${CMAKE_BUILD_TYPE}")
  endif()

  if(_expected_configuration STREQUAL "Debug")
    set(_expected_crt "/MDd")
  elseif(_expected_configuration STREQUAL "Release")
    set(_expected_crt "/MD")
  else()
    message(FATAL_ERROR
      "Only Debug and Release SQLCipher stages are supported; actual configuration: "
      "${_expected_configuration}")
  endif()

  _sqlcipher_manifest_value("SQLCipher tag" _sqlcipher_tag)
  _sqlcipher_manifest_value("Configuration" _sqlcipher_configuration)
  _sqlcipher_manifest_value("Architecture" _sqlcipher_architecture)
  _sqlcipher_manifest_value("CRT" _sqlcipher_crt)
  _sqlcipher_manifest_value("OpenSSL tag" _sqlcipher_openssl_tag)
  _sqlcipher_manifest_value("OpenSSL manifest SHA-256" _sqlcipher_openssl_manifest_hash)
  _sqlcipher_manifest_value("Windows SDK" _sqlcipher_sdk)

  if(NOT _sqlcipher_tag STREQUAL "v4.18.0")
    message(FATAL_ERROR
      "SQLCipher v4.18.0 is required; manifest reports: ${_sqlcipher_tag}")
  endif()

  if(NOT _sqlcipher_configuration STREQUAL _expected_configuration)
    message(FATAL_ERROR
      "SQLCipher configuration mismatch: expected ${_expected_configuration}, "
      "manifest reports ${_sqlcipher_configuration}.")
  endif()

  if(NOT _sqlcipher_architecture STREQUAL "x64")
    message(FATAL_ERROR
      "SQLCipher x64 is required; manifest reports: ${_sqlcipher_architecture}")
  endif()

  if(NOT _sqlcipher_crt STREQUAL _expected_crt)
    message(FATAL_ERROR
      "SQLCipher CRT mismatch: expected ${_expected_crt}, manifest reports ${_sqlcipher_crt}.")
  endif()

  if(NOT _sqlcipher_openssl_tag STREQUAL "openssl-3.5.7")
    message(FATAL_ERROR
      "SQLCipher must use OpenSSL 3.5.7; manifest reports: ${_sqlcipher_openssl_tag}")
  endif()

  if(NOT DEFINED OPENSSL_ROOT_DIR
      OR NOT EXISTS "${OPENSSL_ROOT_DIR}/build-manifest.txt")
    message(FATAL_ERROR
      "The selected OpenSSL stage manifest is required to validate SQLCipher.")
  endif()
  file(SHA256 "${OPENSSL_ROOT_DIR}/build-manifest.txt" _selected_openssl_manifest_hash)
  if(NOT _selected_openssl_manifest_hash STREQUAL _sqlcipher_openssl_manifest_hash)
    message(FATAL_ERROR
      "SQLCipher was not built against the selected OpenSSL stage manifest.")
  endif()

  if(NOT _sqlcipher_sdk STREQUAL CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION)
    string(CONCAT _sqlcipher_sdk_message
      "SQLCipher was built with Windows SDK ${_sqlcipher_sdk}, but the application targets "
      "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}.")
    if(SQLITEBROWSER_DEPENDENCY_SDK_POLICY STREQUAL "STRICT")
      message(FATAL_ERROR "${_sqlcipher_sdk_message}")
    else()
      message(WARNING "${_sqlcipher_sdk_message}")
    endif()
  endif()

  set(SQLCIPHER_INCLUDE_DIRS "${SQLCIPHER_INCLUDE_DIR}")
  set(SQLCIPHER_LIBRARIES "${SQLCIPHER_LIBRARY}")

  if(NOT TARGET SQLCipher::SQLCipher)
    add_library(SQLCipher::SQLCipher SHARED IMPORTED)
    set_target_properties(SQLCipher::SQLCipher PROPERTIES
      IMPORTED_IMPLIB "${SQLCIPHER_LIBRARY}"
      IMPORTED_LOCATION "${SQLCIPHER_RUNTIME_LIBRARY}"
      INTERFACE_INCLUDE_DIRECTORIES "${SQLCIPHER_INCLUDE_DIR}")
  endif()

  mark_as_advanced(
    SQLCIPHER_INCLUDE_DIR
    SQLCIPHER_LIBRARY
    SQLCIPHER_RUNTIME_LIBRARY
    SQLCIPHER_MANIFEST)

  message(STATUS "SQLCipher package:")
  message(STATUS "  Version: ${SQLCIPHER_VERSION}")
  message(STATUS "  Root: ${SQLCIPHER_ROOT_DIR}")
  message(STATUS "  Configuration: ${_sqlcipher_configuration}")
  message(STATUS "  Runtime: ${SQLCIPHER_RUNTIME_LIBRARY}")

  return()
endif()

# use pkg-config to get the directories and then use these values
# in the FIND_PATH() and FIND_LIBRARY() calls
if( NOT WIN32 )
  find_package(PkgConfig)

  pkg_check_modules(PC_SQLCIPHER QUIET sqlcipher)

  set(SQLCIPHER_DEFINITIONS ${PC_SQLCIPHER_CFLAGS_OTHER})
endif( NOT WIN32 )

find_path(SQLCIPHER_INCLUDE_DIR NAMES sqlcipher/sqlite3.h
  PATHS
  ${SQLCIPHER_ROOT_DIR}
  ${PC_SQLCIPHER_INCLUDEDIR}
  ${PC_SQLCIPHER_INCLUDE_DIRS}
  ${CMAKE_INCLUDE_PATH}
  PATH_SUFFIXES "include"
)

find_library(SQLCIPHER_LIBRARY NAMES sqlcipher
  PATHS
  ${PC_SQLCIPHER_LIBDIR}
  ${PC_SQLCIPHER_LIBRARY_DIRS}
  ${SQLCIPHER_ROOT_DIR}
  PATH_SUFFIXES "lib"
)

set(SQLCIPHER_LIBRARIES ${SQLCIPHER_LIBRARY})
set(SQLCIPHER_INCLUDE_DIRS ${SQLCIPHER_INCLUDE_DIR})

if (SQLCIPHER_USE_OPENSSL)
    find_package(OpenSSL REQUIRED COMPONENTS Crypto)
    if (SQLCIPHER_OPENSSL_USE_ZLIB)
        find_package(ZLIB REQUIRED)
        # Official FindOpenSSL.cmake does not support Zlib
        set_target_properties(OpenSSL::Crypto PROPERTIES INTERFACE_LINK_LIBRARIES ZLIB::ZLIB)
    endif()

    list(APPEND SQLCIPHER_LIBRARIES ${OPENSSL_LIBRARIES})
    list(APPEND SQLCIPHER_INCLUDE_DIRS ${OPENSSL_INCLUDE_DIRS})
endif()


include(FindPackageHandleStandardArgs)

find_package_handle_standard_args(SQLCipher
    DEFAULT_MSG SQLCIPHER_INCLUDE_DIR SQLCIPHER_LIBRARY)

# show the SQLCIPHER_INCLUDE_DIR and SQLCIPHER_LIBRARIES variables only in the advanced view
mark_as_advanced(SQLCIPHER_INCLUDE_DIR SQLCIPHER_LIBRARY)

if (NOT TARGET SQLCipher::SQLCipher)
    add_library(SQLCipher::SQLCipher UNKNOWN IMPORTED)

    set_property(TARGET SQLCipher::SQLCipher PROPERTY INTERFACE_COMPILE_DEFINITIONS SQLITE_HAS_CODEC)
    set_property(TARGET SQLCipher::SQLCipher APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS "SQLITE_TEMPSTORE=2")
    set_target_properties(SQLCipher::SQLCipher PROPERTIES
                          INTERFACE_INCLUDE_DIRECTORIES "${SQLCIPHER_INCLUDE_DIRS}"
                          IMPORTED_INTERFACE_LINK_LANGUAGES "C"
                          IMPORTED_LOCATION "${SQLCIPHER_LIBRARY}")

    if (SQLCIPHER_USE_OPENSSL)
        set_target_properties(SQLCipher::SQLCipher PROPERTIES
                              INTERFACE_LINK_LIBRARIES OpenSSL::Crypto)
        set_property(TARGET SQLCipher::SQLCipher APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS "SQLCIPHER_CRYPTO_OPENSSL")
    endif()
endif()
