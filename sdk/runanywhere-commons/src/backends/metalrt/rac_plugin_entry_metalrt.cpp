/**
 * @file rac_plugin_entry_metalrt.cpp
 * @brief Unified-ABI entry point for MetalRT backend (Apple only).
 *
 * GAP 02 Phase 9 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * MetalRT is a multi-primitive engine: it serves LLM + STT + TTS + VLM all
 * from custom Metal shaders. `capability_check()` gates on __APPLE__ so
 * misconfigured Linux builds that link this TU fail silently.
 */

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/core/rac_error.h"

extern "C" {

extern const rac_llm_service_ops_t g_metalrt_llm_ops;
extern const rac_stt_service_ops_t g_metalrt_stt_ops;
extern const rac_tts_service_ops_t g_metalrt_tts_ops;
extern const rac_vlm_service_ops_t g_metalrt_vlm_ops;

static rac_result_t metalrt_capability_check(void) {
#if defined(__APPLE__)
    return RAC_SUCCESS;
#else
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#endif
}

static const rac_runtime_id_t k_metalrt_runtimes[] = {
    RAC_RUNTIME_METAL,
    RAC_RUNTIME_ANE,
};

static const uint32_t k_metalrt_formats[] = {
    6,  /* MODEL_FORMAT_COREML    */
    8,  /* MODEL_FORMAT_MLPACKAGE */
    1,  /* MODEL_FORMAT_GGUF      — for the LLM ops slot */
};

static const rac_engine_vtable_t g_metalrt_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "metalrt",
        .display_name     = "MetalRT",
        .engine_version   = nullptr,
        .priority         = 120,  /* Highest — hand-tuned Metal shaders. */
        .capability_flags = 0,
        .runtimes         = k_metalrt_runtimes,
        .runtimes_count   = sizeof(k_metalrt_runtimes) / sizeof(k_metalrt_runtimes[0]),
        .formats          = k_metalrt_formats,
        .formats_count    = sizeof(k_metalrt_formats) / sizeof(k_metalrt_formats[0]),
    },
    /* capability_check */ metalrt_capability_check,
    /* on_unload        */ nullptr,

    /* llm_ops          */ &g_metalrt_llm_ops,
    /* stt_ops          */ &g_metalrt_stt_ops,
    /* tts_ops          */ &g_metalrt_tts_ops,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ &g_metalrt_vlm_ops,
    /* diffusion_ops    */ nullptr,

    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(metalrt) {
    return &g_metalrt_engine_vtable;
}

}  // extern "C"
