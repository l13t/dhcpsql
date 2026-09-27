# Keep assertions enabled even in Release builds.
add_compile_options(-UNDEBUG)

add_executable(test_common test_common.c
    ${CMAKE_SOURCE_DIR}/src/common/common.c
    ${CMAKE_SOURCE_DIR}/src/common/pidfile.c)
add_test(NAME test_common COMMAND test_common)

add_executable(test_options test_options.c test_support.c
    ${CMAKE_SOURCE_DIR}/src/common/options.c)
add_test(NAME test_options COMMAND test_options)

if(ENABLE_MYSQL)
    add_executable(test_mysql test_mysql.c test_support.c
        ${CMAKE_SOURCE_DIR}/src/common/options.c
        ${CMAKE_SOURCE_DIR}/src/server/static_leases_mysql.c
        ${CMAKE_SOURCE_DIR}/src/server/serverpacket_mysql.c
        ${CMAKE_SOURCE_DIR}/src/server/leases.c)
    target_include_directories(test_mysql BEFORE PRIVATE stubs)
    add_test(NAME test_mysql COMMAND test_mysql)
endif()

find_program(VALGRIND_EXECUTABLE valgrind)
if(VALGRIND_EXECUTABLE)
    add_test(NAME memory_leak_test
        COMMAND ${VALGRIND_EXECUTABLE} --leak-check=full --error-exitcode=1
        $<TARGET_FILE:test_options>)
endif()

find_program(BASH_EXECUTABLE bash)
if(BASH_EXECUTABLE)
    add_test(NAME test_runner COMMAND ${BASH_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/test_runner.sh)
endif()
