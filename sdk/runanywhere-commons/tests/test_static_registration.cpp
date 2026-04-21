/**
 * @file test_static_registration.cpp
 * @brief Verifies that RAC_STATIC_PLUGIN_REGISTER schedules registration
 *        before main() and survives compile-time dead-code analysis.
 *
 * GAP 03 Phase 6.
 *
 * Scenario:
 *   * The fixture below uses RAC_STATIC_PLUGIN_REGISTER(test_static).
 *   * `g_test_static_vtable` is exposed via a private rac_plugin_entry_test_static
 *     so the macro has a vtable to register.
 *   * When `main()` runs, the plugin MUST already be in the registry.
 *
 * This test runs in BOTH static and shared-plugin builds — the macro is C++
 * static-init, independent of the dlopen path.
 */

#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_loader.h"
#include "rac/plugin/rac_primitive.h"

namespace {
const int k_sentinel_static = 0xFEEDFACE;
}

extern "C" {

static const rac_engine_vtable_t g_test_static_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "test_static",
        .display_name     = "GAP 03 static-register fixture",
        .engine_version   = "0.0.0",
        .priority         = 1,
        .capability_flags = 0,
        .reserved_0       = 0,
        .reserved_1       = 0,
    },
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,
    /* llm_ops          */ reinterpret_cast<const struct rac_llm_service_ops*>(&k_sentinel_static),
    /* stt_ops          */ nullptr, /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr, /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr, /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(test_static) {
    return &g_test_static_vtable;
}

}  // extern "C"

RAC_STATIC_PLUGIN_REGISTER(test_static);

int main() {
    std::fprintf(stdout, "test_static_registration\n");
    /* If the macro worked, the plugin is already registered before main() runs. */
    const char** names = nullptr;
    size_t n = 0;
    rac_registry_list_plugins(&names, &n);
    bool found = false;
    for (size_t i = 0; i < n; ++i) {
        if (std::strcmp(names[i], "test_static") == 0) found = true;
    }
    rac_registry_free_plugin_list(names, n);
    if (!found) {
        std::fprintf(stderr,
                     "test_static not in registry at main() — RAC_STATIC_PLUGIN_REGISTER did not run\n");
        return 1;
    }
    std::fprintf(stdout, "  ok: static-register fired before main()\n");
    /* Cleanup so subsequent tests in the same CTest run see a clean registry. */
    rac_plugin_unregister("test_static");
    return 0;
}
