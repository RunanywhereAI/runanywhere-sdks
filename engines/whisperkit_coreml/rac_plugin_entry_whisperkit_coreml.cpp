/**
 * @file rac_plugin_entry_whisperkit_coreml.cpp
 * @brief Unified-ABI entry point for WhisperKit CoreML STT backend (Apple
 * only).
 *
 * GAP 02 Phase 9 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * `capability_check()` returns RAC_ERROR_CAPABILITY_UNSUPPORTED on non-Apple
 * hosts so the plugin silently declines registration when building Linux or
 * Windows hosts that link this TU by accident.
 *
 * CPP-04: declarative manifest publishes package ownership, Apple-only
 * availability and the served primitive set alongside the routing metadata.
 */

#include "rac_runtime_coreml.h"

#include "rac/backends/rac_stt_whisperkit_coreml.h"
#include "rac/core/rac_error.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

extern const rac_stt_service_ops_t g_whisperkit_coreml_stt_ops;

static rac_result_t whisperkit_coreml_capability_check(void) {
#if defined(__APPLE__)
    rac_result_t runtime_rc = rac_coreml_runtime_require_available();
    if (runtime_rc != RAC_SUCCESS)
        return runtime_rc;
    return rac_whisperkit_coreml_stt_is_available() == RAC_TRUE ? RAC_SUCCESS
                                                                : RAC_ERROR_BACKEND_UNAVAILABLE;
#else
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#endif
}

static const rac_runtime_id_t k_whisperkit_coreml_runtimes[] = {
    RAC_RUNTIME_COREML,
    RAC_RUNTIME_ANE,
};

static const uint32_t k_whisperkit_coreml_formats[] = {
    RAC_MODEL_FORMAT_ID_COREML,
    RAC_MODEL_FORMAT_ID_MLPACKAGE,
};

static const rac_primitive_t k_whisperkit_coreml_primitives[] = {
    RAC_PRIMITIVE_TRANSCRIBE,
};

static const rac_engine_manifest_t k_whisperkit_coreml_manifest = {
    .name = "whisperkit_coreml",
    .display_name = "WhisperKit (CoreML)",
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_whisperkit_coreml",
    .availability = RAC_ENGINE_AVAILABILITY_PRIVATE, /* Apple-only. */
    .priority = 110,                                 /* Hardware-accelerated, beats CPU backends. */
    .capability_flags = 0,
    .primitives = k_whisperkit_coreml_primitives,
    .primitives_count =
        sizeof(k_whisperkit_coreml_primitives) / sizeof(k_whisperkit_coreml_primitives[0]),
    .runtimes = k_whisperkit_coreml_runtimes,
    .runtimes_count =
        sizeof(k_whisperkit_coreml_runtimes) / sizeof(k_whisperkit_coreml_runtimes[0]),
    .formats = k_whisperkit_coreml_formats,
    .formats_count = sizeof(k_whisperkit_coreml_formats) / sizeof(k_whisperkit_coreml_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_whisperkit_coreml_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_whisperkit_coreml_manifest),
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

RAC_PLUGIN_ENTRY_DEF(whisperkit_coreml) {
    return rac_engine_entry_with_manifest(&k_whisperkit_coreml_manifest,
                                          &g_whisperkit_coreml_engine_vtable);
}

}  // extern "C"
