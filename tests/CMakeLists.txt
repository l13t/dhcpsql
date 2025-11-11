cmake_minimum_required(VERSION 3.12)

# Test configuration
enable_testing()

# Add test directory to include path
include_directories(${CMAKE_SOURCE_DIR}/include)

# Test source files
set(TEST_SOURCES
    test_common.c
    test_options.c
    test_packet.c
)

# Common test dependencies
set(TEST_DEPS
    ${CMAKE_SOURCE_DIR}/src/common/common.c
    ${CMAKE_SOURCE_DIR}/src/common/options.c
    ${CMAKE_SOURCE_DIR}/src/common/packet.c
)

# Create test executables
foreach(test_source ${TEST_SOURCES})
    get_filename_component(test_name ${test_source} NAME_WE)
    add_executable(${test_name} ${test_source} ${TEST_DEPS})
    add_test(NAME ${test_name} COMMAND ${test_name})
endforeach()

# Integration tests
add_executable(integration_test integration_test.c ${TEST_DEPS})
add_test(NAME integration_test COMMAND integration_test)

# Memory leak tests (requires valgrind)
find_program(VALGRIND_EXECUTABLE valgrind)
if(VALGRIND_EXECUTABLE)
    add_test(NAME memory_leak_test 
             COMMAND ${VALGRIND_EXECUTABLE} --leak-check=full --error-exitcode=1 
             $<TARGET_FILE:test_common>)
endif()
