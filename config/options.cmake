set(QT_MAJOR Qt5 CACHE STRING "Major QT version")
OPTION(BUILD_STABLE_VERSION "Don't build the stable version by default" OFF) # Choose between building a stable version or nightly (the default), depending on whether '-DBUILD_STABLE_VERSION=1' is passed on the command line or not.
OPTION(ENABLE_TESTING "Enable the unit tests" OFF)
OPTION(FORCE_INTERNAL_QSCINTILLA "Don't use the distribution's QScintilla library even if there is one" OFF)
OPTION(FORCE_INTERNAL_QCUSTOMPLOT "Don't use distribution's QCustomPlot even if available" ON)
OPTION(FORCE_INTERNAL_QHEXEDIT "Don't use distribution's QHexEdit even if available" ON)
OPTION(ALL_WARNINGS "Enable some useful warning flags" OFF)
OPTION(sqlcipher "Build with SQLCipher library" OFF)
OPTION(customTap "Using SQLCipher, SQLite and Qt installed through our custom Homebrew tap" OFF)
OPTION(SQLITEBROWSER_DEPLOY_RUNTIME
    "Deploy and validate the Windows runtime next to the application after linking"
    ON)

set(SQLITEBROWSER_TLS_SMOKE_URL
    "https://download.sqlitebrowser.org/currentrelease"
    CACHE STRING "HTTPS endpoint used by the explicit Windows runtime smoke target")

set(SQLITEBROWSER_DEPENDENCY_SDK_POLICY "WARN" CACHE STRING
    "Dependency SDK mismatch policy: WARN or STRICT")
set_property(CACHE SQLITEBROWSER_DEPENDENCY_SDK_POLICY PROPERTY STRINGS WARN STRICT)
if(NOT SQLITEBROWSER_DEPENDENCY_SDK_POLICY MATCHES "^(WARN|STRICT)$")
    message(FATAL_ERROR
        "SQLITEBROWSER_DEPENDENCY_SDK_POLICY must be WARN or STRICT.")
endif()
