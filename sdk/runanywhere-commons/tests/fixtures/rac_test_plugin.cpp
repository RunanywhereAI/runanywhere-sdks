/**
 * @file rac_test_plugin.cpp
 * @brief Minimal test-fixture plugin used by GAP 03 loader tests.
 *
 * Compiled into TWO shared libraries:
 *   - librunanywhere_test_plugin.so    (good ABI, accepted by registry)
 *   - librunanywhere_test_plugin_bad_abi.so  (forced ABI = host + 99,
 *     rejected by registry as proof of the version handshake)
 *
 * Both define the entry symbol `rac_plugin_entry_test_plugin` so the
 * `entry_symbol_from_path()` heuristic in `plugin_loader.cpp` resolves
 * correctly.
 *
 * The vtable points at NO real ops — `llm_ops` is set to a sentinel so
 * `rac_engine_vtable_slot()` returns non-NULL but no inference is ever
 * performed. The fixture exists purely to exercise the registration /
 * dedup / dlclose paths.
 */

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

/* Sentinel address to put in llm_ops so the vtable serves the
 * GENERATE_TEXT primitive without exercising any real LLM code. */
static const int k_test_plugin_sentinel = 0xCAFEBABE;

#ifndef RAC_TEST_PLUGIN_FORCE_BAD_ABI
#  define RAC_TEST_PLUGIN_ABI_VERSION RAC_PLUGIN_API_VERSION
#else
/* Compile-time toggle to force ABI mismatch — used by the abi-mismatch
 * test fixture build. */
#  define RAC_TEST_PLUGIN_ABI_VERSION (RAC_PLUGIN_API_VERSION + 99u)
#endif

static const rac_engine_vtable_t g_test_plugin_vtable = {
    /* metadata */ {
        .abi_version      = RAC_TEST_PLUGIN_ABI_VERSION,
        .name             = "test_plugin",
        .display_name     = "GAP 03 fixture",
        .engine_version   = "0.0.0",
        .priority         = 1,
        .capability_flags = 0,
        .runtimes         = nullptr,   /* fixture cares about routing-agnostic registration */
        .runtimes_count   = 0,
        .formats          = nullptr,
        .formats_count    = 0,
    },
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,
    /* llm_ops          */ reinterpret_cast<const struct rac_llm_service_ops*>(&k_test_plugin_sentinel),
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,
    /* reserved_slot_0..9 */
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

/* Default visibility so dlsym can find this symbol. */
__attribute__((visibility("default")))
RAC_PLUGIN_ENTRY_DEF(test_plugin) {
    return &g_test_plugin_vtable;
}

}  // extern "C"
