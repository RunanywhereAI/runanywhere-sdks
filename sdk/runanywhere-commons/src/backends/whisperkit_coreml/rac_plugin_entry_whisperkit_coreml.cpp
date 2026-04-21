/**
 * @file rac_plugin_entry_whisperkit_coreml.cpp
 * @brief Unified-ABI entry point for WhisperKit CoreML STT backend (Apple only).
 *
 * GAP 02 Phase 9 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * `capability_check()` returns RAC_ERROR_CAPABILITY_UNSUPPORTED on non-Apple
 * hosts so the plugin silently declines registration when building Linux or
 * Windows hosts that link this TU by accident.
 */

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/core/rac_error.h"

extern "C" {

extern const rac_stt_service_ops_t g_whisperkit_coreml_stt_ops;

static rac_result_t whisperkit_coreml_capability_check(void) {
#if defined(__APPLE__)
    return RAC_SUCCESS;
#else
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#endif
}

static const rac_engine_vtable_t g_whisperkit_coreml_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "whisperkit_coreml",
        .display_name     = "WhisperKit (CoreML)",
        .engine_version   = nullptr,
        .priority         = 110,  /* Hardware-accelerated, beats CPU backends. */
        .capability_flags = 0,
        .reserved_0       = 0,
        .reserved_1       = 0,
    },
    /* capability_check */ whisperkit_coreml_capability_check,
    /* on_unload        */ nullptr,

    /* llm_ops          */ nullptr,
    /* stt_ops          */ &g_whisperkit_coreml_stt_ops,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,

    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(whisperkit_coreml) {
    return &g_whisperkit_coreml_engine_vtable;
}

}  // extern "C"
