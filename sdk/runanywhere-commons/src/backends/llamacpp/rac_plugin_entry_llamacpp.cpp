/**
 * @file rac_plugin_entry_llamacpp.cpp
 * @brief Unified-ABI entry point for the llama.cpp LLM engine.
 *
 * GAP 02 Phase 8 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * Exposes `rac_plugin_entry_llamacpp()` returning a `const rac_engine_vtable_t*`
 * filled with the existing `g_llamacpp_ops` (non-static since Phase 8) as the
 * LLM slot. All other primitive slots remain NULL.
 *
 * Coexistence with legacy path:
 *   The existing `rac_backend_llamacpp_register()` entry point continues to
 *   register the llama.cpp LLM service via `rac_service_register_provider()`.
 *   The new entry point registers the same ops-struct into the unified plugin
 *   registry. Both paths can be active simultaneously; callers selecting via
 *   the new registry get the same code, but zero legacy behavior is disturbed.
 */

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/llm/rac_llm_service.h"

extern "C" {

/* Defined in rac_backend_llamacpp_register.cpp (non-static since Phase 8). */
extern const rac_llm_service_ops_t g_llamacpp_ops;

/* Static vtable in .rodata — registry records the pointer, does not copy. */
static const rac_engine_vtable_t g_llamacpp_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "llamacpp",
        .display_name     = "llama.cpp",
        .engine_version   = nullptr,   /* filled by llama_cpp's own header */
        .priority         = 100,
        .capability_flags = 0,
        .reserved_0       = 0,
        .reserved_1       = 0,
    },
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,

    /* llm_ops          */ &g_llamacpp_ops,
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

RAC_PLUGIN_ENTRY_DEF(llamacpp) {
    return &g_llamacpp_engine_vtable;
}

}  // extern "C"
