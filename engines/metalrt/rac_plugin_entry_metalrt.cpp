/**
 * @file rac_plugin_entry_metalrt.cpp
 * @brief Unified-ABI entry point for MetalRT backend (Apple only).
 *
 * GAP 02 Phase 9 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * MetalRT is a multi-primitive engine: it serves LLM + STT + TTS + VLM all
 * from custom Metal shaders. `capability_check()` gates on both __APPLE__
 * and the private engine binary so stub builds do not advertise primitives.
 *
 * CPP-04: declarative manifest publishes package ownership, Apple-only
 * (private) availability and the served primitive set alongside the routing
 * metadata. The manifest mirrors the conditional ops slots so registry
 * validation accepts both routable and stub builds.
 */

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(__APPLE__) && defined(RAC_METALRT_ENGINE_AVAILABLE) && RAC_METALRT_ENGINE_AVAILABLE
#define RAC_METALRT_ROUTABLE 1
#else
#define RAC_METALRT_ROUTABLE 0
#endif

extern "C" {

extern const rac_llm_service_ops_t g_metalrt_llm_ops;
extern const rac_stt_service_ops_t g_metalrt_stt_ops;
extern const rac_tts_service_ops_t g_metalrt_tts_ops;
extern const rac_vlm_service_ops_t g_metalrt_vlm_ops;

static rac_result_t metalrt_capability_check(void) {
#if !defined(__APPLE__)
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#elif defined(RAC_METALRT_ENGINE_AVAILABLE) && RAC_METALRT_ENGINE_AVAILABLE
    return RAC_SUCCESS;
#else
    return RAC_ERROR_BACKEND_UNAVAILABLE;
#endif
}

#if RAC_METALRT_ROUTABLE
static const rac_runtime_id_t k_metalrt_runtimes[] = {
    RAC_RUNTIME_METAL,
    RAC_RUNTIME_ANE,
};

static const uint32_t k_metalrt_formats[] = {
    RAC_MODEL_FORMAT_ID_COREML, RAC_MODEL_FORMAT_ID_MLPACKAGE,
    RAC_MODEL_FORMAT_ID_GGUF, /* for the LLM ops slot */
};

static const rac_primitive_t k_metalrt_primitives[] = {
    RAC_PRIMITIVE_GENERATE_TEXT,
    RAC_PRIMITIVE_TRANSCRIBE,
    RAC_PRIMITIVE_SYNTHESIZE,
    RAC_PRIMITIVE_VLM,
};
#endif

static const rac_engine_manifest_t k_metalrt_manifest = {
    .name = "metalrt",
    .display_name =
#if RAC_METALRT_ROUTABLE
        "MetalRT",
#else
        "MetalRT [ops unavailable]",
#endif
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_metalrt",
    .availability = RAC_ENGINE_AVAILABILITY_PRIVATE, /* Apple-only. */
    .priority =
#if RAC_METALRT_ROUTABLE
        120, /* Highest — hand-tuned Metal shaders. */
#else
        0,
#endif
    .capability_flags = 0,
    .primitives =
#if RAC_METALRT_ROUTABLE
        k_metalrt_primitives,
#else
        nullptr,
#endif
    .primitives_count =
#if RAC_METALRT_ROUTABLE
        sizeof(k_metalrt_primitives) / sizeof(k_metalrt_primitives[0]),
#else
        0,
#endif
    .runtimes =
#if RAC_METALRT_ROUTABLE
        k_metalrt_runtimes,
#else
        nullptr,
#endif
    .runtimes_count =
#if RAC_METALRT_ROUTABLE
        sizeof(k_metalrt_runtimes) / sizeof(k_metalrt_runtimes[0]),
#else
        0,
#endif
    .formats =
#if RAC_METALRT_ROUTABLE
        k_metalrt_formats,
#else
        nullptr,
#endif
    .formats_count =
#if RAC_METALRT_ROUTABLE
        sizeof(k_metalrt_formats) / sizeof(k_metalrt_formats[0]),
#else
        0,
#endif
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_metalrt_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_metalrt_manifest),
    /* capability_check */ metalrt_capability_check,
    /* on_unload        */ nullptr,

/* llm_ops          */
#if RAC_METALRT_ROUTABLE
    &g_metalrt_llm_ops,
#else
    nullptr,
#endif
/* stt_ops          */
#if RAC_METALRT_ROUTABLE
    &g_metalrt_stt_ops,
#else
    nullptr,
#endif
/* tts_ops          */
#if RAC_METALRT_ROUTABLE
    &g_metalrt_tts_ops,
#else
    nullptr,
#endif
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
/* vlm_ops          */
#if RAC_METALRT_ROUTABLE
    &g_metalrt_vlm_ops,
#else
    nullptr,
#endif
    /* diffusion_ops    */ nullptr,

    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
};

RAC_PLUGIN_ENTRY_DEF(metalrt) {
    return rac_engine_entry_with_manifest(&k_metalrt_manifest, &g_metalrt_engine_vtable);
}

}  // extern "C"
