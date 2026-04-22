/**
 * @file rac_plugin_entry_sherpa.cpp
 * @brief GAP 06 Phase 10 stub for the Sherpa-ONNX STT engine plugin.
 *
 * Provides the unified-ABI entry point so the router treats sherpa as a
 * first-class plugin candidate (`rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE,
 * MODEL_FORMAT_ONNX, ...)` will see it). The ops slot is NULL until the
 * peel-from-onnx work in a follow-up phase wires
 * `g_sherpa_stt_ops`. Until then the plugin's `capability_check()` returns
 * RAC_ERROR_CAPABILITY_UNSUPPORTED so the registry quietly declines it.
 */

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

static rac_result_t sherpa_capability_check(void) {
    /* TODO: drop this once g_sherpa_stt_ops is wired. */
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
}

static const rac_runtime_id_t k_sherpa_runtimes[] = { RAC_RUNTIME_CPU };
static const uint32_t         k_sherpa_formats[]  = { 3 /* MODEL_FORMAT_ONNX */ };

static const rac_engine_vtable_t g_sherpa_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "sherpa",
        .display_name     = "Sherpa-ONNX (STT scaffold)",
        .engine_version   = nullptr,
        .priority         = 70,
        .capability_flags = 0,
        .runtimes         = k_sherpa_runtimes,
        .runtimes_count   = sizeof(k_sherpa_runtimes) / sizeof(k_sherpa_runtimes[0]),
        .formats          = k_sherpa_formats,
        .formats_count    = sizeof(k_sherpa_formats) / sizeof(k_sherpa_formats[0]),
    },
    /* capability_check */ sherpa_capability_check,
    /* on_unload        */ nullptr,
    /* llm_ops          */ nullptr,
    /* stt_ops          */ nullptr,  /* TODO: wire g_sherpa_stt_ops post-slice */
    /* tts_ops          */ nullptr, /* vad_ops */ nullptr, /* embedding_ops */ nullptr,
    /* rerank_ops       */ nullptr, /* vlm_ops */ nullptr, /* diffusion_ops */ nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(sherpa) { return &g_sherpa_engine_vtable; }

}  // extern "C"
