/**
 * @file test_plugin_loader_double_load.cpp
 * @brief Verifies double-load is idempotent (registry dedups by name; the
 *        loader's redundant dlopen is balanced by an extra dlclose so the
 *        OS reference count stays at 1 after one explicit unload).
 *
 * GAP 03 Phase 6.
 */

#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_loader.h"
#include "rac/plugin/rac_primitive.h"

#ifndef RAC_TEST_PLUGIN_PATH
#  error "RAC_TEST_PLUGIN_PATH must be set by tests/CMakeLists.txt"
#endif

int main() {
    std::fprintf(stdout, "test_plugin_loader_double_load: %s\n", RAC_TEST_PLUGIN_PATH);

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
    std::fprintf(stdout, "  skip: static-plugins build\n");
    return 0;
#else
    /* (1) First load → success. */
    rac_result_t rc = rac_registry_load_plugin(RAC_TEST_PLUGIN_PATH);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "first load failed: %d\n", static_cast<int>(rc));
        return 1;
    }
    size_t count_after_first = rac_registry_plugin_count();

    /* (2) Second load → registry dedups by metadata.name. The current dedup
     * policy returns RAC_ERROR_PLUGIN_DUPLICATE when the second registration
     * has lower priority; here it has equal priority so the registry MAY
     * accept (replace) it. Either outcome is acceptable; what matters is
     * that the count does not grow. */
    rc = rac_registry_load_plugin(RAC_TEST_PLUGIN_PATH);
    if (rc != RAC_SUCCESS && rc != RAC_ERROR_PLUGIN_DUPLICATE) {
        std::fprintf(stderr,
                     "second load returned unexpected code: %d\n",
                     static_cast<int>(rc));
        return 1;
    }
    size_t count_after_second = rac_registry_plugin_count();
    if (count_after_second != count_after_first) {
        std::fprintf(stderr,
                     "registry leaked: count after first=%zu, after second=%zu\n",
                     count_after_first, count_after_second);
        return 1;
    }

    /* (3) Single unregister suffices to remove the entry. */
    rc = rac_registry_unload_plugin("test_plugin");
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "unload failed: %d\n", static_cast<int>(rc));
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != nullptr) {
        std::fprintf(stderr, "still in registry after unload\n");
        return 1;
    }

    /* (4) Unloading a name that no longer exists returns NOT_FOUND, never crash. */
    rc = rac_registry_unload_plugin("test_plugin");
    if (rc != RAC_ERROR_NOT_FOUND) {
        std::fprintf(stderr,
                     "second unload returned unexpected: %d (want NOT_FOUND)\n",
                     static_cast<int>(rc));
        return 1;
    }

    std::fprintf(stdout, "  ok: double-load deduped, single unload sufficient\n");
    return 0;
#endif
}
