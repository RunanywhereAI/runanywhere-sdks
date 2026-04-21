/**
 * @file test_plugin_loader.cpp
 * @brief Happy-path test for the GAP 03 dynamic plugin loader.
 *
 * Loads the in-tree fixture .so, asserts the plugin appears under its
 * registered name, and unloads it cleanly. Skipped on RAC_PLUGIN_MODE_STATIC
 * builds (where dlopen is disabled by design).
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_loader.h"
#include "rac/plugin/rac_primitive.h"

#ifndef RAC_TEST_PLUGIN_PATH
#  error "RAC_TEST_PLUGIN_PATH must be set by tests/CMakeLists.txt"
#endif

int main() {
    std::fprintf(stdout, "test_plugin_loader: %s\n", RAC_TEST_PLUGIN_PATH);

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
    std::fprintf(stdout,
                 "  skip: RAC_PLUGIN_MODE_STATIC is set; loader returns FEATURE_NOT_AVAILABLE by design\n");
    return 0;
#else
    /* (1) ABI version helper agrees with the macro. */
    if (rac_plugin_api_version() != RAC_PLUGIN_API_VERSION) {
        std::fprintf(stderr, "abi_version mismatch: %u vs %u\n",
                     rac_plugin_api_version(), RAC_PLUGIN_API_VERSION);
        return 1;
    }

    /* (2) Load. */
    rac_result_t rc = rac_registry_load_plugin(RAC_TEST_PLUGIN_PATH);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_registry_load_plugin failed: %d\n", static_cast<int>(rc));
        return 1;
    }

    /* (3) Plugin is now in the registry under the name from its metadata. */
    const rac_engine_vtable_t* vt = rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT);
    if (vt == nullptr || std::strcmp(vt->metadata.name, "test_plugin") != 0) {
        std::fprintf(stderr, "rac_plugin_find did not return the test fixture\n");
        return 1;
    }

    /* (4) List + free. */
    const char** names = nullptr;
    size_t n = 0;
    rc = rac_registry_list_plugins(&names, &n);
    if (rc != RAC_SUCCESS || n == 0) {
        std::fprintf(stderr, "rac_registry_list_plugins returned 0\n");
        return 1;
    }
    bool found = false;
    for (size_t i = 0; i < n; ++i) {
        if (std::strcmp(names[i], "test_plugin") == 0) found = true;
    }
    rac_registry_free_plugin_list(names, n);
    if (!found) {
        std::fprintf(stderr, "test_plugin not in list snapshot\n");
        return 1;
    }

    /* (5) Unload. dlclose happens inside; subsequent find returns NULL. */
    rc = rac_registry_unload_plugin("test_plugin");
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "rac_registry_unload_plugin failed: %d\n", static_cast<int>(rc));
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != nullptr) {
        std::fprintf(stderr, "plugin still registered after unload\n");
        return 1;
    }

    std::fprintf(stdout, "  ok: load → find → list → unload round-trip clean\n");
    return 0;
#endif
}
