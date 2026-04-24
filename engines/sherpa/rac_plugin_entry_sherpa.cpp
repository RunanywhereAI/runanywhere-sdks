/**
 * @file rac_plugin_entry_sherpa.cpp
 * @brief Unified-ABI entry point for the Sherpa-ONNX backend.
 *
 * GAP 02 Phase 9 + GAP 06 T5.1 — see the matching specs.
 *
 * The sherpa engine is the long-term owner of Sherpa-ONNX-backed STT /
 * TTS / VAD. T5.1 landed the physical plugin + build artifact; the
 * primitive op migrations from engines/onnx/ onnx_backend.cpp are
 * tracked as Phase 2 of T5.1. Until that lands this vtable exposes
 * NULL primitive slots — the router simply sees a registered "sherpa"
 * engine with no services, which the registration path tolerates (it's
 * the same shape whisperkit_coreml uses on non-Apple platforms).
 */

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

static const rac_runtime_id_t k_sherpa_runtimes[] = {
    RAC_RUNTIME_CPU,
};

static const uint32_t k_sherpa_formats[] = {
    3,  /* MODEL_FORMAT_ONNX */
};

static const rac_engine_vtable_t g_sherpa_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "sherpa",
        .display_name     = "Sherpa-ONNX",
        .engine_version   = nullptr,
        /* Below onnx (80) so requests for ONNX models still route there
         * during T5.1 phase 1 where onnx continues to serve Sherpa-backed
         * STT/TTS/VAD. Phase 2 flips this above onnx once the primitive
         * migration lands and onnx gives up its speech slots. */
        .priority         = 70,
        .capability_flags = 0,
        .runtimes         = k_sherpa_runtimes,
        .runtimes_count   = sizeof(k_sherpa_runtimes) / sizeof(k_sherpa_runtimes[0]),
        .formats          = k_sherpa_formats,
        .formats_count    = sizeof(k_sherpa_formats) / sizeof(k_sherpa_formats[0]),
    },
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,

    /* T5.1 Phase 2: the four ops below get wired when SherpaSTT /
     * SherpaTTS / SherpaVAD land in this directory. */
    /* llm_ops          */ nullptr,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,

    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(sherpa) {
    return &g_sherpa_engine_vtable;
}

}  // extern "C"
