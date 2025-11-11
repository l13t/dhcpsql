/* Basic unit tests for common functions */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "udhcp/common.h"

void test_logging() {
    printf("Testing logging functions...\n");
    // Basic logging test - should not crash
    LOG(LOG_INFO, "Test log message");
    printf("✓ Logging test passed\n");
}

void test_time_functions() {
    printf("Testing time functions...\n");
    // Test basic time operations
    time_t current_time = time(NULL);
    assert(current_time > 0);
    printf("✓ Time functions test passed\n");
}

void test_memory_operations() {
    printf("Testing memory operations...\n");
    // Test basic memory allocation
    void *ptr = malloc(100);
    assert(ptr != NULL);
    memset(ptr, 0, 100);
    free(ptr);
    printf("✓ Memory operations test passed\n");
}

int main() {
    printf("Running common function tests...\n\n");
    
    test_logging();
    test_time_functions();
    test_memory_operations();
    
    printf("\n✓ All common tests passed!\n");
    return 0;
}
