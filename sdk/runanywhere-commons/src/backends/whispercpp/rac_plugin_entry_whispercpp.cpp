/**
 * @file rac_plugin_entry_whispercpp.cpp
 * @brief Unified-ABI entry point for whisper.cpp STT backend.
 *
 * GAP 02 Phase 9 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 */

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/stt/rac_stt_service.h"

extern "C" {

extern const rac_stt_service_ops_t g_whispercpp_stt_ops;

static const rac_engine_vtable_t g_whispercpp_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "whispercpp",
        .display_name     = "whisper.cpp",
        .engine_version   = nullptr,
        .priority         = 90,
        .capability_flags = 0,
        .reserved_0       = 0,
        .reserved_1       = 0,
    },
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,

    /* llm_ops          */ nullptr,
    /* stt_ops          */ &g_whispercpp_stt_ops,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,

    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(whispercpp) {
    return &g_whispercpp_engine_vtable;
}

}  // extern "C"
