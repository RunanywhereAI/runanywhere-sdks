/**
 * @file rac_memory.cpp
 * @brief RunAnywhere Commons - Memory Utilities
 *
 * Matches Swift's memory management patterns for C interop.
 */

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_types.h"

extern "C" {

/**
 * Allocate memory using the RAC allocator.
 */
void* rac_alloc(size_t size) {
    if (size == 0) {
        return nullptr;
    }
    return malloc(size);
}

/**
 * Free memory allocated by RAC functions.
 * Matches the pattern from Swift's ra_free_string usage.
 */
void rac_free(void* ptr) {
    if (ptr != nullptr) {
        free(ptr);
    }
}

/**
 * Duplicate a string (caller must free with rac_free).
 * Matches Swift interop patterns.
 */
char* rac_strdup(const char* str) {
    if (str == nullptr) {
        return nullptr;
    }

    size_t len = strlen(str) + 1;
    char* copy = static_cast<char*>(malloc(len));
    if (copy != nullptr) {
        memcpy(copy, str, len);
    }
    return copy;
}

}  // extern "C"
