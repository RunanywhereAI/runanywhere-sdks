/**
 * @file rac_plugin_entry_sherpa.cpp
 * @brief Unified-ABI entry point for the Sherpa-ONNX backend.
 *
 * GAP 02 Phase 9 + GAP 06 T5.1 — see the matching specs.
 *
 * The sherpa engine owns Sherpa-ONNX-backed STT / TTS / VAD primitives.
 * It only advertises those primitives when both the Sherpa-ONNX prebuilt and
 * the real RAC speech ops are compiled into this target.
 */

#include "rac/core/rac_error.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(SHERPA_ONNX_AVAILABLE) && SHERPA_ONNX_AVAILABLE && \
    defined(RAC_SHERPA_SPEECH_OPS_AVAILABLE) && RAC_SHERPA_SPEECH_OPS_AVAILABLE
#define RAC_SHERPA_ROUTABLE 1
#else
#define RAC_SHERPA_ROUTABLE 0
#endif

extern "C" {

#if RAC_SHERPA_ROUTABLE
extern const rac_stt_service_ops_t g_sherpa_stt_ops;
extern const rac_tts_service_ops_t g_sherpa_tts_ops;
extern const rac_vad_service_ops_t g_sherpa_vad_ops;
#endif

static rac_result_t sherpa_capability_check(void) {
#if RAC_SHERPA_ROUTABLE
    return RAC_SUCCESS;
#else
    return RAC_ERROR_BACKEND_UNAVAILABLE;
#endif
}

#if RAC_SHERPA_ROUTABLE
static const rac_runtime_id_t k_sherpa_runtimes[] = {
    RAC_RUNTIME_CPU,
};

static const uint32_t k_sherpa_formats[] = {
    3,  /* MODEL_FORMAT_ONNX */
};
#endif

static const rac_engine_vtable_t g_sherpa_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "sherpa",
        .display_name     = "Sherpa-ONNX",
        .engine_version   = nullptr,
        .priority         =
#if RAC_SHERPA_ROUTABLE
            90,
#else
            0,
#endif
        .capability_flags = 0,
        .runtimes         =
#if RAC_SHERPA_ROUTABLE
            k_sherpa_runtimes,
#else
            nullptr,
#endif
        .runtimes_count   =
#if RAC_SHERPA_ROUTABLE
            sizeof(k_sherpa_runtimes) / sizeof(k_sherpa_runtimes[0]),
#else
            0,
#endif
        .formats          =
#if RAC_SHERPA_ROUTABLE
            k_sherpa_formats,
#else
            nullptr,
#endif
        .formats_count    =
#if RAC_SHERPA_ROUTABLE
            sizeof(k_sherpa_formats) / sizeof(k_sherpa_formats[0]),
#else
            0,
#endif
    },
    /* capability_check */ sherpa_capability_check,
    /* on_unload        */ nullptr,

    /* llm_ops          */ nullptr,
    /* stt_ops          */
#if RAC_SHERPA_ROUTABLE
    &g_sherpa_stt_ops,
#else
    nullptr,
#endif
    /* tts_ops          */
#if RAC_SHERPA_ROUTABLE
    &g_sherpa_tts_ops,
#else
    nullptr,
#endif
    /* vad_ops          */
#if RAC_SHERPA_ROUTABLE
    &g_sherpa_vad_ops,
#else
    nullptr,
#endif
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
