cmake_minimum_required(VERSION 3.30.3)

project(sqlitebrowser
    VERSION 4.0.0
    DESCRIPTION "GUI editor for SQLite databases"
    LANGUAGES CXX
)

include(GNUInstallDirs)

include(config/options.cmake)

if(NOT WIN32)
    message(FATAL_ERROR "This v4.0.0 build path currently supports Windows only.")
endif()

if(NOT MSVC)
    message(FATAL_ERROR "Visual Studio 2022 with MSVC is required.")
endif()

if(NOT CMAKE_GENERATOR STREQUAL "Visual Studio 17 2022")
    message(FATAL_ERROR
        "Visual Studio 17 2022 is required; actual generator: ${CMAKE_GENERATOR}")
endif()

if(NOT CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
    message(FATAL_ERROR
        "The x64 generator platform is required; actual platform: ${CMAKE_GENERATOR_PLATFORM}")
endif()

if(NOT CMAKE_VS_PLATFORM_TOOLSET STREQUAL "v143")
    message(FATAL_ERROR
        "The v143 platform toolset is required; actual toolset: ${CMAKE_VS_PLATFORM_TOOLSET}")
endif()

if(NOT CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION STREQUAL "10.0.26100.0")
    message(FATAL_ERROR
        "Windows SDK 10.0.26100.0 is required; actual SDK: ${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "A 64-bit compiler is required.")
endif()

if(NOT QT_MAJOR STREQUAL "Qt6")
    message(FATAL_ERROR "Qt6 is required; actual QT_MAJOR: ${QT_MAJOR}")
endif()

if(NOT DEFINED SQLITEBROWSER_CONFIGURATION_ROOT
        OR SQLITEBROWSER_CONFIGURATION_ROOT STREQUAL "")
    message(FATAL_ERROR
        "SQLITEBROWSER_CONFIGURATION_ROOT must identify the current unified output root.")
endif()

cmake_path(ABSOLUTE_PATH SQLITEBROWSER_CONFIGURATION_ROOT
    BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    NORMALIZE
    OUTPUT_VARIABLE _sqlitebrowser_configuration_root)
cmake_path(ABSOLUTE_PATH CMAKE_BINARY_DIR
    NORMALIZE
    OUTPUT_VARIABLE _sqlitebrowser_binary_dir)
set(_sqlitebrowser_expected_binary_dir
    "${_sqlitebrowser_configuration_root}/build/sqlitebrowser")
cmake_path(NORMAL_PATH _sqlitebrowser_expected_binary_dir)
cmake_path(COMPARE
    "${_sqlitebrowser_binary_dir}"
    EQUAL
    "${_sqlitebrowser_expected_binary_dir}"
    _sqlitebrowser_binary_dir_matches)
if(NOT _sqlitebrowser_binary_dir_matches)
    message(FATAL_ERROR
        "The application binary directory must be "
        "${_sqlitebrowser_expected_binary_dir}; actual: ${_sqlitebrowser_binary_dir}")
endif()

foreach(_dependency_aggregate_file IN ITEMS
        "${_sqlitebrowser_configuration_root}/metadata/dependency-aggregate-manifest.txt"
        "${_sqlitebrowser_configuration_root}/metadata/dependency-ownership-manifest.txt")
    if(NOT EXISTS "${_dependency_aggregate_file}")
        message(FATAL_ERROR
            "The configuration dependency aggregate is incomplete: "
            "${_dependency_aggregate_file}\n"
            "Run third_party\\aggregate.cmd build for this configuration first.")
    endif()
endforeach()

set(SQLITEBROWSER_CONFIGURATION_ROOT
    "${_sqlitebrowser_configuration_root}"
    CACHE PATH "Current SQLiteBrowser unified output root" FORCE)
set(SQLITEBROWSER_PUBLIC_BIN_DIR
    "${SQLITEBROWSER_CONFIGURATION_ROOT}/bin")

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)

set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" "${CMAKE_MODULE_PATH}")

if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()

find_package(Qt6 6.11.1 EXACT CONFIG REQUIRED
    COMPONENTS
        Concurrent
        Core5Compat
        Gui
        LinguistTools
        Network
        PrintSupport
        Widgets
        Xml
)

if(ENABLE_TESTING)
    find_package(Qt6 6.11.1 EXACT CONFIG REQUIRED COMPONENTS Test)
endif()

if(NOT TARGET Qt6::windeployqt)
    message(FATAL_ERROR "Qt6::windeployqt is required but was not provided by the selected Qt package.")
endif()

message(STATUS "SQLiteBrowser toolchain:")
message(STATUS "  Generator: ${CMAKE_GENERATOR}")
message(STATUS "  Platform: ${CMAKE_GENERATOR_PLATFORM}")
message(STATUS "  Toolset: ${CMAKE_VS_PLATFORM_TOOLSET}")
message(STATUS "  Windows SDK: ${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}")
message(STATUS "  Qt: ${Qt6_VERSION}")
message(STATUS "  Qt package: ${Qt6_DIR}")
message(STATUS "  Configuration root: ${SQLITEBROWSER_CONFIGURATION_ROOT}")
message(STATUS "  Application build tree: ${CMAKE_BINARY_DIR}")
message(STATUS "  Development bin: ${SQLITEBROWSER_PUBLIC_BIN_DIR}")

qt_add_executable(${PROJECT_NAME} WIN32)
set_target_properties(${PROJECT_NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${SQLITEBROWSER_PUBLIC_BIN_DIR}"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${SQLITEBROWSER_PUBLIC_BIN_DIR}"
    PDB_OUTPUT_DIRECTORY_DEBUG "${SQLITEBROWSER_PUBLIC_BIN_DIR}"
    PDB_OUTPUT_DIRECTORY_RELEASE "${SQLITEBROWSER_PUBLIC_BIN_DIR}"
    MSVC_DEBUG_INFORMATION_FORMAT "$<$<CONFIG:Debug,Release>:ProgramDatabase>"
)
target_link_options(${PROJECT_NAME} PRIVATE "$<$<CONFIG:Release>:/DEBUG>")
if(MSVC)
    # Serialize writes to the target compiler PDB when MSBuild schedules
    # multiple cl.exe processes for the same project.
    target_compile_options(${PROJECT_NAME} PRIVATE /FS)
endif()

execute_process(
    COMMAND git -C ${CMAKE_CURRENT_SOURCE_DIR} rev-parse --short --verify HEAD
    OUTPUT_VARIABLE GIT_COMMIT_HASH
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)

if (GIT_COMMIT_HASH STREQUAL "")
    MESSAGE(WARNING "Could not determine git commit hash")
    set(GIT_COMMIT_HASH "Unknown")
endif()

add_definitions(-DGIT_COMMIT_HASH="${GIT_COMMIT_HASH}")
if(NOT BUILD_STABLE_VERSION)
    # BUILD_VERSION is the current date in YYYYMMDD format. It is only
    # used by the nightly version to add the date of the build.
    # Default defined in Version.h.in
    string(TIMESTAMP BUILD_VERSION "%Y%m%d")
    target_compile_definitions(${PROJECT_NAME} PRIVATE BUILD_VERSION=${BUILD_VERSION})
endif()

include(config/platform.cmake)

set(QT_LIBS
    Qt6::Gui
    Qt6::PrintSupport
    Qt6::Widgets
    Qt6::Network
    Qt6::Concurrent
    Qt6::Xml
    Qt6::Core5Compat
)
set_target_properties(${PROJECT_NAME} PROPERTIES
    AUTOUIC_OPTIONS "--connections=string"
)

target_include_directories(${PROJECT_NAME} SYSTEM PRIVATE ${CMAKE_CURRENT_LIST_DIR}/libs/json)
target_include_directories(${PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_BINARY_DIR} src)

include(config/3dparty.cmake)

# SQLCipher option
if(sqlcipher)
    target_compile_definitions(${PROJECT_NAME} PRIVATE ENABLE_SQLCIPHER)
    find_package(SQLCipher REQUIRED)
    set(LIBSQLITE_NAME SQLCipher::SQLCipher)
else()
    find_package(SQLite3 REQUIRED)
    set(LIBSQLITE_NAME SQLite::SQLite3)
endif()

configure_file(${CMAKE_CURRENT_SOURCE_DIR}/src/version.h.in
    ${CMAKE_CURRENT_BINARY_DIR}/version.h
)

target_sources(${PROJECT_NAME}
    PRIVATE
    src/sql/sqlitetypes.h
    src/sql/Query.h
    src/sql/ObjectIdentifier.h
    src/csvparser.h
    src/sqlite.h
    src/Data.h
    src/IconCache.h
    src/sql/parser/ParserDriver.h
    src/sql/parser/sqlite3_lexer.h
    src/sql/parser/sqlite3_location.h
    src/sql/parser/sqlite3_parser.hpp
)

target_sources(${PROJECT_NAME}
    PRIVATE
    src/sqlitedb.h
    src/AboutDialog.h
    src/EditIndexDialog.h
    src/EditDialog.h
    src/EditTableDialog.h
    src/AddRecordDialog.h
    src/ExportDataDialog.h
    src/ExtendedTableWidget.h
    src/FilterTableHeader.h
    src/ImportCsvDialog.h
    src/MainWindow.h
    src/Settings.h
    src/PreferencesDialog.h
    src/SqlExecutionArea.h
    src/VacuumDialog.h
    src/sqlitetablemodel.h
    src/RowLoader.h
    src/RowCache.h
    src/sqltextedit.h
    src/docktextedit.h
    src/DbStructureModel.h
    src/dbstructureqitemviewfacade.h
    src/Application.h
    src/CipherDialog.h
    src/ExportSqlDialog.h
    src/SqlUiLexer.h
    src/FileDialog.h
    src/ColumnDisplayFormatDialog.h
    src/FilterLineEdit.h
    src/ForeignKeyEditorDelegate.h
    src/PlotDock.h
    src/FindReplaceDialog.h
    src/ExtendedScintilla.h
    src/FileExtensionManager.h
    src/CondFormatManager.h
    src/CipherSettings.h
    src/Palette.h
    src/CondFormat.h
    src/RunSql.h
    src/ProxyDialog.h
    src/SelectItemsPopup.h
    src/TableBrowser.h
    src/ImageViewer.h
    src/RemoteNetwork.h
    src/TableBrowserDock.h
)

target_sources(${PROJECT_NAME}
    PRIVATE
    src/AboutDialog.cpp
    src/EditIndexDialog.cpp
    src/EditDialog.cpp
    src/EditTableDialog.cpp
    src/AddRecordDialog.cpp
    src/ExportDataDialog.cpp
    src/ExtendedTableWidget.cpp
    src/FilterTableHeader.cpp
    src/ImportCsvDialog.cpp
    src/MainWindow.cpp
    src/Settings.cpp
    src/PreferencesDialog.cpp
    src/SqlExecutionArea.cpp
    src/VacuumDialog.cpp
    src/sqlitedb.cpp
    src/sqlitetablemodel.cpp
    src/RowLoader.cpp
    src/sql/sqlitetypes.cpp
    src/sql/Query.cpp
    src/sql/ObjectIdentifier.cpp
    src/sqltextedit.cpp
    src/docktextedit.cpp
    src/csvparser.cpp
    src/DbStructureModel.cpp
    src/dbstructureqitemviewfacade.cpp
    src/main.cpp
    src/Application.cpp
    src/CipherDialog.cpp
    src/ExportSqlDialog.cpp
    src/SqlUiLexer.cpp
    src/FileDialog.cpp
    src/ColumnDisplayFormatDialog.cpp
    src/FilterLineEdit.cpp
    src/ForeignKeyEditorDelegate.cpp
    src/PlotDock.cpp
    src/FindReplaceDialog.cpp
    src/ExtendedScintilla.cpp
    src/FileExtensionManager.cpp
    src/CondFormatManager.cpp
    src/Data.cpp
    src/CipherSettings.cpp
    src/Palette.cpp
    src/CondFormat.cpp
    src/RunSql.cpp
    src/ProxyDialog.cpp
    src/IconCache.cpp
    src/SelectItemsPopup.cpp
    src/TableBrowser.cpp
    src/sql/parser/ParserDriver.cpp
    src/sql/parser/sqlite3_lexer.cpp
    src/sql/parser/sqlite3_parser.cpp
    src/ImageViewer.cpp
    src/RemoteNetwork.cpp
    src/TableBrowserDock.cpp
)

source_group("Qt UI" "src/.*\.ui$")
target_sources(${PROJECT_NAME}
    PRIVATE
    src/AboutDialog.ui
    src/EditIndexDialog.ui
    src/EditDialog.ui
    src/EditTableDialog.ui
    src/AddRecordDialog.ui
    src/ExportDataDialog.ui
    src/ImportCsvDialog.ui
    src/MainWindow.ui
    src/PreferencesDialog.ui
    src/SqlExecutionArea.ui
    src/VacuumDialog.ui
    src/CipherDialog.ui
    src/ExportSqlDialog.ui
    src/ColumnDisplayFormatDialog.ui
    src/PlotDock.ui
    src/FindReplaceDialog.ui
    src/FileExtensionManager.ui
    src/CondFormatManager.ui
    src/ProxyDialog.ui
    src/SelectItemsPopup.ui
    src/TableBrowser.ui
    src/ImageViewer.ui
)

include(config/translations.cmake)

source_group("Qt Resources" "src/.*\.qrc$")
target_sources(${PROJECT_NAME}
    PRIVATE

    # General
    src/sql/parser/sqlite3_parser.yy
    src/sql/parser/sqlite3_lexer.ll

    # Graphics
    src/icons/icons.qrc

    # Translations
    src/translations/flags/flags.qrc

    # Styles
    src/qdarkstyle/dark/darkstyle.qrc
    src/qdarkstyle/light/lightstyle.qrc
)

target_link_libraries(${PROJECT_NAME}
    PRIVATE
    ${QT_LIBS}
    QHexEdit::QHexEdit QCustomPlot::QCustomPlot QScintilla::QScintilla
    ${LIBSQLITE_NAME}
    ${PLATFORM_LIBS}
)

if(SQLITEBROWSER_DEPLOY_RUNTIME)
    if(NOT sqlcipher)
        message(FATAL_ERROR
            "SQLITEBROWSER_DEPLOY_RUNTIME requires the staged SQLCipher build.")
    endif()

    include(cmake/SQLiteBrowserWindowsRuntime.cmake)
    sqlitebrowser_configure_windows_runtime(
        TARGET ${PROJECT_NAME}
        SQLCIPHER_TARGET SQLCipher::SQLCipher
    )

    set(SQLITEBROWSER_PACKAGE_RUNTIME_DIR
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/package/runtime")
    set(SQLITEBROWSER_PACKAGE_RUNTIME_MANIFEST
        "${SQLITEBROWSER_CONFIGURATION_ROOT}/package/metadata/runtime-manifest.txt")
    sqlitebrowser_add_windows_package_runtime(
        TARGET ${PROJECT_NAME}
        RUNTIME_DIR "${SQLITEBROWSER_PACKAGE_RUNTIME_DIR}"
        MANIFEST "${SQLITEBROWSER_PACKAGE_RUNTIME_MANIFEST}"
    )

    if(ENABLE_TESTING)
        sqlitebrowser_add_windows_runtime_smoke(
            APP_TARGET ${PROJECT_NAME}
            SQLCIPHER_TARGET SQLCipher::SQLCipher
            SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/src/tests/runtime_smoke.cpp"
            TLS_URL "${SQLITEBROWSER_TLS_SMOKE_URL}"
            RUNTIME_DIR "${SQLITEBROWSER_PACKAGE_RUNTIME_DIR}"
            RUNTIME_TARGET sqlitebrowser_package_runtime
        )
    endif()

    if(TARGET sqlitebrowser_runtime_smoke)
        include(cmake/SQLiteBrowserZip.cmake)
        sqlitebrowser_add_windows_zip(
            TARGET ${PROJECT_NAME}
            RUNTIME_TARGET sqlitebrowser_runtime_smoke
            RUNTIME_DIR "${SQLITEBROWSER_PACKAGE_RUNTIME_DIR}"
            MANIFEST "${SQLITEBROWSER_PACKAGE_RUNTIME_MANIFEST}"
            SMOKE_TARGET sqlitebrowser-runtime-smoke-tool
            TLS_URL "${SQLITEBROWSER_TLS_SMOKE_URL}"
            SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}"
        )

        include(cmake/SQLiteBrowserPortableSfx.cmake)
        sqlitebrowser_add_windows_portable_sfx(
            TARGET ${PROJECT_NAME}
            RUNTIME_TARGET sqlitebrowser_runtime_smoke
            RUNTIME_DIR "${SQLITEBROWSER_PACKAGE_RUNTIME_DIR}"
            MANIFEST "${SQLITEBROWSER_PACKAGE_RUNTIME_MANIFEST}"
            SMOKE_TARGET sqlitebrowser-runtime-smoke-tool
            TLS_URL "${SQLITEBROWSER_TLS_SMOKE_URL}"
            NSIS_SCRIPT
                "${CMAKE_CURRENT_SOURCE_DIR}/installer/windows/nsis/portable-sfx.nsi"
            SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}"
        )

        include(cmake/SQLiteBrowserWix.cmake)
        sqlitebrowser_add_windows_msi(
            TARGET ${PROJECT_NAME}
            RUNTIME_TARGET sqlitebrowser_runtime_smoke
            RUNTIME_DIR "${SQLITEBROWSER_PACKAGE_RUNTIME_DIR}"
            MANIFEST "${SQLITEBROWSER_PACKAGE_RUNTIME_MANIFEST}"
            WIX_PROJECT
                "${CMAKE_CURRENT_SOURCE_DIR}/installer/windows/wix/SQLiteBrowser.Installer.wixproj"
            SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}"
        )
    endif()
endif()

include(config/install.cmake)

if(ENABLE_TESTING)
    enable_testing()
    add_subdirectory(src/tests)
endif()

# CPack configuration
set(CPACK_STRIP_FILES ON)
set(CPACK_DEBIAN_PACKAGE_PRIORITY optional)
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
set(CPACK_DEBIAN_PACKAGE_GENERATE_SHLIBS ON)
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "Tristan Stenner <dbbrowser@nicht.dienstli.ch>")
set(CPACK_ARCHIVE_COMPONENT_INSTALL ON)
if(APPLE)
    set(CPACK_DEFAULT_GEN TBZ2)
elseif(WIN32)
    set(CPACK_DEFAULT_GEN ZIP)
elseif(UNIX)
    set(CPACK_DEFAULT_GEN DEB)
    set(CPACK_SET_DESTDIR 1)
    set(CPACK_INSTALL_PREFIX "/usr")
endif()
set(CPACK_GENERATOR ${CPACK_DEFAULT_GEN} CACHE STRING "CPack pkg type(s) to generate")
include(CPack)
