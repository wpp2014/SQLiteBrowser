cmake_minimum_required(VERSION 3.30.3)

foreach(_required_variable IN ITEMS
        APP_EXECUTABLE
        SMOKE_EXECUTABLE
        RUNTIME_DIR
        SMOKE_WORK_DIR
        TLS_URL)
    if(NOT DEFINED ${_required_variable}
        OR "${${_required_variable}}" STREQUAL "")
        message(FATAL_ERROR "Missing required smoke variable: ${_required_variable}")
    endif()
endforeach()

foreach(_required_file IN ITEMS "${APP_EXECUTABLE}" "${SMOKE_EXECUTABLE}")
    if(NOT EXISTS "${_required_file}")
        message(FATAL_ERROR "Runtime smoke executable does not exist: ${_required_file}")
    endif()
endforeach()
if(NOT IS_DIRECTORY "${RUNTIME_DIR}")
    message(FATAL_ERROR "Runtime smoke directory does not exist: ${RUNTIME_DIR}")
endif()

file(MAKE_DIRECTORY "${SMOKE_WORK_DIR}")
set(_settings_file "${SMOKE_WORK_DIR}/settings.ini")
file(WRITE "${_settings_file}"
    "[%General]\n"
    "language=en_US\n"
    "\n"
    "[checkversion]\n"
    "enabled=false\n")

# Only the deployed application directory is exposed through PATH. System DLLs
# continue to resolve through the Windows loader's system-directory rules.
set(ENV{PATH} "${RUNTIME_DIR}")
set(ENV{QT_PLUGIN_PATH} "${RUNTIME_DIR}")
set(ENV{QT_TLS_BACKEND} "openssl")
unset(ENV{DB4S_SETTINGS_FILE})
unset(ENV{OPENSSL_CONF})
unset(ENV{OPENSSL_MODULES})

function(_sqlitebrowser_run_smoke_case case_name executable timeout_seconds)
    execute_process(
        COMMAND "${executable}" ${ARGN}
        WORKING_DIRECTORY "${RUNTIME_DIR}"
        TIMEOUT "${timeout_seconds}"
        RESULT_VARIABLE _result
        OUTPUT_VARIABLE _stdout
        ERROR_VARIABLE _stderr
        ENCODING UTF-8
    )
    string(STRIP "${_stdout}" _stdout)
    string(STRIP "${_stderr}" _stderr)
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR
            "${case_name} failed (result: ${_result}).\n"
            "stdout:\n${_stdout}\n"
            "stderr:\n${_stderr}")
    endif()

    if(NOT _stdout STREQUAL "")
        message(STATUS "${case_name}: ${_stdout}")
    else()
        message(STATUS "${case_name}: passed")
    endif()
endfunction()

_sqlitebrowser_run_smoke_case(
    "Application startup smoke"
    "${APP_EXECUTABLE}"
    30
    --quit
    --settings "${_settings_file}"
)
_sqlitebrowser_run_smoke_case(
    "SQLCipher database smoke"
    "${SMOKE_EXECUTABLE}"
    30
    --mode database
    --runtime-dir "${RUNTIME_DIR}"
)
_sqlitebrowser_run_smoke_case(
    "OpenSSL Brotli smoke"
    "${SMOKE_EXECUTABLE}"
    30
    --mode brotli
    --runtime-dir "${RUNTIME_DIR}"
)
_sqlitebrowser_run_smoke_case(
    "Qt OpenSSL HTTPS smoke"
    "${SMOKE_EXECUTABLE}"
    60
    --mode tls
    --runtime-dir "${RUNTIME_DIR}"
    --url "${TLS_URL}"
)

message(STATUS "SQLiteBrowser restricted-PATH runtime smoke suite passed.")
