/**
 * @file test_plugin_loader_abi_mismatch.cpp
 * @brief Verifies the loader rejects a plugin whose ABI version does not
 *        match the host's RAC_PLUGIN_API_VERSION.
 *
 * GAP 03 Phase 6 — see v2_gap_specs/GAP_03_DYNAMIC_PLUGIN_LOADING.md.
 *
 * The fixture under RAC_TEST_PLUGIN_BAD_ABI_PATH is the same as the good
 * fixture but compiled with -DRAC_TEST_PLUGIN_FORCE_BAD_ABI so its
 * `metadata.abi_version` equals the host's plus 99. The registry MUST
 * return RAC_ERROR_ABI_VERSION_MISMATCH and MUST NOT add it to the
 * primitive table.
 */

#include <cstdio>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_loader.h"
#include "rac/plugin/rac_primitive.h"

#ifndef RAC_TEST_PLUGIN_BAD_ABI_PATH
#  error "RAC_TEST_PLUGIN_BAD_ABI_PATH must be set by tests/CMakeLists.txt"
#endif

int main() {
    std::fprintf(stdout, "test_plugin_loader_abi_mismatch: %s\n",
                 RAC_TEST_PLUGIN_BAD_ABI_PATH);

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
    std::fprintf(stdout, "  skip: static-plugins build\n");
    return 0;
#else
    rac_result_t rc = rac_registry_load_plugin(RAC_TEST_PLUGIN_BAD_ABI_PATH);
    if (rc != RAC_ERROR_ABI_VERSION_MISMATCH) {
        std::fprintf(stderr,
                     "expected RAC_ERROR_ABI_VERSION_MISMATCH (%d), got %d\n",
                     static_cast<int>(RAC_ERROR_ABI_VERSION_MISMATCH),
                     static_cast<int>(rc));
        return 1;
    }
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) != nullptr) {
        std::fprintf(stderr, "rejected plugin still appears in registry\n");
        return 1;
    }
    std::fprintf(stdout, "  ok: ABI mismatch rejected, registry untouched\n");
    return 0;
#endif
}
