/**
 * @file rac_plugin_entry_llamacpp_vlm.cpp
 * @brief Unified-ABI entry point for the llama.cpp Vision-Language Model engine.
 *
 * GAP 02 Phase 8 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * Exposes `rac_plugin_entry_llamacpp_vlm()` filling only the VLM slot with
 * the existing `g_llamacpp_vlm_ops`. Separate from the LLM entry point so the
 * two can be independently gated in builds that only want one.
 */

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/vlm/rac_vlm_service.h"

extern "C" {

/* Defined in rac_backend_llamacpp_vlm_register.cpp (non-static since Phase 8). */
extern const rac_vlm_service_ops_t g_llamacpp_vlm_ops;

static const rac_runtime_id_t k_llamacpp_vlm_runtimes[] = {
    RAC_RUNTIME_CPU,
#if defined(__APPLE__)
    RAC_RUNTIME_METAL,
#endif
};

static const uint32_t k_llamacpp_vlm_formats[] = {
    1,  /* MODEL_FORMAT_GGUF */
    5,  /* MODEL_FORMAT_BIN  — vision projector / mmproj files */
};

static const rac_engine_vtable_t g_llamacpp_vlm_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "llamacpp_vlm",
        .display_name     = "llama.cpp (VLM)",
        .engine_version   = nullptr,
        .priority         = 100,
        .capability_flags = 0,
        .runtimes         = k_llamacpp_vlm_runtimes,
        .runtimes_count   = sizeof(k_llamacpp_vlm_runtimes) / sizeof(k_llamacpp_vlm_runtimes[0]),
        .formats          = k_llamacpp_vlm_formats,
        .formats_count    = sizeof(k_llamacpp_vlm_formats) / sizeof(k_llamacpp_vlm_formats[0]),
    },
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,

    /* llm_ops          */ nullptr,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ &g_llamacpp_vlm_ops,
    /* diffusion_ops    */ nullptr,

    /* reserved_slot_0..9 */
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(llamacpp_vlm) {
    return &g_llamacpp_vlm_engine_vtable;
}

}  // extern "C"
