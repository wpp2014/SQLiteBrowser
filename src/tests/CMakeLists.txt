set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

function(sqlitebrowser_configure_unit_test target)
    target_include_directories(${target}
        PRIVATE
            "${CMAKE_CURRENT_BINARY_DIR}"
            "${CMAKE_CURRENT_SOURCE_DIR}/.."
    )
    set_target_properties(${target} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/tests"
        RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/tests"
    )
    add_test(NAME ${target} COMMAND $<TARGET_FILE:${target}>)
    set_tests_properties(${target} PROPERTIES
        ENVIRONMENT_MODIFICATION
            "PATH=path_list_prepend:$<TARGET_FILE_DIR:Qt6::Core>"
        TIMEOUT 60
    )
endfunction()

# test-sqlobjects

set(TESTSQLOBJECTS_SRC
    ../sql/sqlitetypes.cpp
    ../sql/Query.cpp
    ../sql/ObjectIdentifier.cpp
    testsqlobjects.cpp
    ../sql/parser/ParserDriver.cpp
    ../sql/parser/sqlite3_lexer.cpp
    ../sql/parser/sqlite3_parser.cpp
)

set(TESTSQLOBJECTS_HDR
    ../sql/sqlitetypes.h
    ../sql/Query.h
    ../sql/ObjectIdentifier.h
    ../sql/parser/ParserDriver.h
    ../sql/parser/sqlite3_lexer.h
    ../sql/parser/sqlite3_location.h
    ../sql/parser/sqlite3_parser.hpp
    testsqlobjects.h
)

add_executable(test-sqlobjects ${TESTSQLOBJECTS_HDR} ${TESTSQLOBJECTS_SRC})
target_link_libraries(test-sqlobjects PRIVATE Qt6::Test)
sqlitebrowser_configure_unit_test(test-sqlobjects)

# test-import

set(TESTIMPORT_SRC
    ../csvparser.cpp
    TestImport.cpp
)

set(TESTIMPORT_MOC_HDR
    TestImport.h
)

add_executable(test-import ${TESTIMPORT_MOC_HDR} ${TESTIMPORT_SRC})
target_link_libraries(test-import PRIVATE Qt6::Test)
sqlitebrowser_configure_unit_test(test-import)

# test regex

set(TESTREGEX_SRC
    TestRegex.cpp
    ../Data.cpp
)

set(TESTREGEX_HDR
    ../Data.h
    TestRegex.h
)

add_executable(test-regex ${TESTREGEX_HDR} ${TESTREGEX_SRC})
target_link_libraries(test-regex PRIVATE Qt6::Test Qt6::Widgets Qt6::Core5Compat)
sqlitebrowser_configure_unit_test(test-regex)

# test cache

set(TESTCACHE_SRC
    TestRowCache.cpp
)

set(TESTCACHE_HDR
    TestRowCache.h
)

add_executable(test-cache ${TESTCACHE_HDR} ${TESTCACHE_SRC})
target_link_libraries(test-cache PRIVATE Qt6::Test)
sqlitebrowser_configure_unit_test(test-cache)
